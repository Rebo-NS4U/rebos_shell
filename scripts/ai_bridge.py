#!/usr/bin/env python3
"""Keep the ACP process and unacknowledged UI events outside Quickshell.

The systemd user service owns the agent. --client is a disposable stdio/socket
relay; EOF or termination of that relay never cancels the agent's active turn.
Checkpoints and ACP writes travel in one frame so a UI crash cannot lose the
request bookkeeping for a prompt already delivered to the agent. Chat content
is kept in memory here; normal chat history persistence remains in Ai.qml.
"""
import argparse
import asyncio
from collections import deque
import contextlib
import json
import os
import re
from pathlib import Path
import signal
import socket
import subprocess
import sys
import threading
import time


LIMIT = 64 * 1024 * 1024


def socket_path(channel="default"):
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime:
        raise RuntimeError("XDG_RUNTIME_DIR is not set")
    name = "acp.sock" if channel == "default" else "acp-" + channel + ".sock"
    return Path(runtime) / "rebos-assistant" / name


def encode(value):
    return (json.dumps(value, separators=(",", ":")) + "\n").encode()


class Bridge:
    def __init__(self):
        self.process = None
        self.tasks = []
        self.client = None
        self.state = None
        self.sequence = 0
        self.acknowledged = 0
        self.events = deque()
        self.launch = None
        self.lock = asyncio.Lock()
        self.stopping = False

    def send(self, value):
        if self.client is None:
            return
        # A stalled menu must never block the agent or consume unlimited socket
        # buffers. The event journal is replayed when the menu reconnects.
        if self.client.transport.get_write_buffer_size() > 4 * 1024 * 1024:
            self.client.close()
            self.client = None
            return
        self.client.write(encode(value))

    def publish(self, kind, **payload):
        self.sequence += 1
        event = dict(bridge=kind, seq=self.sequence, **payload)
        self.events.append(event)
        self.send(event)

    def checkpoint(self, frame):
        sequence = frame.get("seq", 0)
        state = frame.get("state")
        if not isinstance(state, dict) or not isinstance(sequence, int):
            raise ValueError("Invalid assistant checkpoint")
        if not self.acknowledged <= sequence <= self.sequence:
            raise ValueError("Invalid assistant event sequence")
        self.state = state
        self.acknowledged = sequence
        while self.events and self.events[0]["seq"] <= sequence:
            self.events.popleft()

    async def start(self, frame):
        command = frame.get("command")
        cwd = frame.get("cwd")
        if not isinstance(command, list) or not command or not all(isinstance(x, str) for x in command):
            raise ValueError("Invalid ACP command")
        if not isinstance(cwd, str) or not Path(cwd).is_dir():
            raise ValueError("Invalid assistant working directory")
        environment = dict(os.environ)
        # The menu may have a different PATH from the systemd user manager.
        # Credentials are never transported in this handshake.
        if isinstance(frame.get("path"), str):
            environment["PATH"] = frame["path"]
        self.launch = frame
        self.process = await asyncio.create_subprocess_exec(
            *command, cwd=cwd, env=environment,
            stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE, limit=LIMIT, start_new_session=True)
        self.tasks = [asyncio.create_task(self.read_stdout()),
                      asyncio.create_task(self.read_stderr())]
        self.tasks.append(asyncio.create_task(self.wait_process()))

    async def read_stdout(self):
        async for line in self.process.stdout:
            try:
                message = json.loads(line)
            except (ValueError, UnicodeError):
                continue
            self.publish("acp", message=message)

    async def read_stderr(self):
        async for line in self.process.stderr:
            self.publish("stderr", text=line.decode(errors="replace").rstrip())

    async def wait_process(self):
        code = await self.process.wait()
        await asyncio.gather(*self.tasks[:2], return_exceptions=True)
        if not self.stopping:
            self.publish("exit", code=code)

    async def stop(self):
        self.stopping = True
        process = self.process
        if process and process.returncode is None:
            with contextlib.suppress(ProcessLookupError):
                os.killpg(process.pid, signal.SIGTERM)
            try:
                await asyncio.wait_for(process.wait(), timeout=5)
            except asyncio.TimeoutError:
                with contextlib.suppress(ProcessLookupError):
                    os.killpg(process.pid, signal.SIGKILL)
                await process.wait()
        if self.tasks:
            with contextlib.suppress(asyncio.TimeoutError):
                await asyncio.wait_for(asyncio.gather(*self.tasks, return_exceptions=True), timeout=5)
        self.process = None
        self.tasks = []
        self.state = None
        self.sequence = 0
        self.acknowledged = 0
        self.events.clear()
        self.stopping = False

    async def attach(self, reader, writer):
        try:
            frame = json.loads(await reader.readline())
            if frame.get("bridge") == "shutdown":
                async with self.lock:
                    await self.stop()
                    if self.client:
                        self.client.close()
                        self.client = None
                return
            if frame.get("bridge") != "attach":
                raise ValueError("Expected assistant attach")
            async with self.lock:
                if self.client:
                    self.client.close()
                self.client = writer
                if self.process is None:
                    await self.start(frame)
                self.send(dict(bridge="attached", state=self.state, seq=self.acknowledged))
                for event in self.events:
                    self.send(event)
                await writer.drain()
            while line := await reader.readline():
                async with self.lock:
                    if writer is not self.client:
                        break
                    frame = json.loads(line)
                    kind = frame.get("bridge")
                    if kind in ("checkpoint", "send"):
                        self.checkpoint(frame)
                        if kind == "send":
                            if not self.process or self.process.returncode is not None:
                                self.publish("exit", code=self.process.returncode if self.process else -1)
                                continue
                            self.process.stdin.write(encode(frame["message"]))
                            await self.process.stdin.drain()
                    elif kind in ("reset", "shutdown"):
                        await self.stop()
                        if kind == "reset":
                            await self.start(self.launch)
                            self.send(dict(bridge="attached", state=None, seq=0))
                        else:
                            break
                    else:
                        raise ValueError("Unknown assistant bridge command")
        except (ValueError, KeyError, OSError, RuntimeError) as error:
            # Only diagnostic errors, never protocol payloads or chat content.
            with contextlib.suppress(OSError):
                writer.write(encode(dict(bridge="error", error=str(error))))
                await writer.drain()
        finally:
            if self.client is writer:
                self.client = None
            writer.close()
            with contextlib.suppress(OSError):
                await writer.wait_closed()


async def serve(path):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(path.parent, 0o700)
    if path.exists():
        # Do not unlink a live server's socket (e.g. accidental manual launch).
        probe = socket.socket(socket.AF_UNIX)
        try:
            probe.connect(str(path))
        except (ConnectionRefusedError, FileNotFoundError):
            path.unlink(missing_ok=True)
        else:
            raise RuntimeError("Assistant bridge is already running")
        finally:
            probe.close()
    bridge = Bridge()
    server = await asyncio.start_unix_server(bridge.attach, path=str(path), limit=LIMIT)
    os.chmod(path, 0o600)
    stopped = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, stopped.set)
    try:
        async with server:
            await stopped.wait()
    finally:
        await bridge.stop()
        if bridge.client:
            bridge.client.close()
        path.unlink(missing_ok=True)


def relay(path, start_service=True, channel="default"):
    connection = socket.socket(socket.AF_UNIX)
    try:
        connection.connect(str(path))
    except (FileNotFoundError, ConnectionRefusedError):
        if not start_service:
            raise
        unit = "rebos-assistant.service" if channel == "default" else "rebos-assistant@" + channel + ".service"
        subprocess.run(["systemctl", "--user", "start", unit],
                       check=True, stdout=subprocess.DEVNULL, timeout=15)
        for attempt in range(100):
            try:
                connection.connect(str(path))
                break
            except (FileNotFoundError, ConnectionRefusedError):
                time.sleep(0.05)
        else:
            raise RuntimeError("Assistant background service did not create its socket")

    def forward_input():
        try:
            for line in sys.stdin.buffer:
                connection.sendall(line)
        except OSError:
            pass
        finally:
            # Closing the UI is a detach, never a session/cancel or process kill.
            with contextlib.suppress(OSError):
                connection.shutdown(socket.SHUT_RDWR)

    threading.Thread(target=forward_input, daemon=True).start()
    try:
        while chunk := connection.recv(65536):
            sys.stdout.buffer.write(chunk)
            sys.stdout.buffer.flush()
    finally:
        connection.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", action="store_true")
    parser.add_argument("--channel", default="default", help="Independent assistant session")
    parser.add_argument("--stop", action="store_true", help="Explicitly stop the agent without starting it")
    parser.add_argument("--socket", type=Path)
    parser.add_argument("--no-start", action="store_true", help="Do not start the systemd service (tests)")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-zA-Z0-9_-]{1,64}", args.channel):
        parser.error("Invalid assistant channel")
    try:
        path = args.socket or socket_path(args.channel)
        if args.stop:
            with socket.socket(socket.AF_UNIX) as connection:
                try:
                    connection.connect(str(path))
                except (FileNotFoundError, ConnectionRefusedError):
                    return 0
                connection.sendall(encode(dict(bridge="shutdown")))
                while connection.recv(1024):
                    pass
        elif args.server:
            asyncio.run(serve(path))
        else:
            relay(path, not args.no_start, args.channel)
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(json.dumps(dict(bridge="error", error=str(error))), flush=True)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
