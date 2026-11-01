const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const base = require('node:path').join(__dirname, '../modules/services/');
const wifi = fs.readFileSync(base + 'NetworkService.qml', 'utf8');
const bluetooth = fs.readFileSync(base + 'BluetoothService.qml', 'utf8');
function load(source, name, context) {
    const match = source.match(new RegExp('    function ' + name + '\\([^]*?\\n    }'));
    assert.ok(match, name);
    const code = match[0].replace(/: (WifiAccessPoint|string|void|bool|var)(?=[,) {])/g, '');
    context[name] = vm.runInContext('(' + code + ')', context);
}
const settle = () => new Promise(resolve => setImmediate(resolve));
function setup() {
    const context = vm.createContext({
        wifiEnabled: true, wifiScanning: false, isUpdating: false,
        lastScanTime: 0, lastError: '', wifiConnectTarget: null,
        SuspendManager: {isSuspending: false}, calls: [], refreshes: 0,
        update() { this.refreshes++; },
        runAsync() { return Promise.resolve(''); }
    });
    context.root = context;
    context.runAsync = (command, environment, input) => { context.calls.push(Array.from(command)); context.input = input; return Promise.resolve(''); };
    context.update = () => { context.refreshes++; };
    for (const name of ['rescanWifi', 'enableWifi', 'connectToWifiNetwork', 'changePassword', 'disconnectWifiNetwork'])
        load(wifi, name, context);
    return context;
}
(async () => {
    let c = setup();
    let finish;
    c.runAsync = command => { c.calls.push(Array.from(command)); return new Promise(resolve => finish = resolve); };
    c.rescanWifi(); c.rescanWifi();
    assert.equal(c.calls.length, 1, 'one scan in flight');
    assert.equal(c.wifiScanning, true);
    finish(''); await settle();
    assert.equal(c.wifiScanning, false);
    c.rescanWifi();
    assert.equal(c.calls.length, 1, 'scan cooldown');
    c.lastScanTime = 0; c.wifiEnabled = false; c.rescanWifi();
    assert.equal(c.calls.length, 1, 'disabled radio does not scan');
    c.wifiEnabled = true; c.SuspendManager.isSuspending = true; c.rescanWifi();
    assert.equal(c.calls.length, 1, 'sleep does not scan');

    c = setup(); c.wifiEnabled = false;
    c.runAsync = command => { c.calls.push(Array.from(command)); return new Promise(resolve => finish = resolve); };
    c.enableWifi(true); c.enableWifi(true);
    assert.equal(c.calls.length, 1, 'duplicate power action blocked');
    assert.equal(c.calls[0].at(-1), 'on');
    finish(''); await settle();
    assert.equal(c.calls.length, 2, 'scan starts only after power command succeeds');
    assert.deepEqual(c.calls[1], ['nmcli', 'device', 'wifi', 'rescan']);
    finish(''); await settle();

    c = setup();
    c.runAsync = () => Promise.reject('radio unavailable');
    c.rescanWifi(); await settle();
    assert.equal(c.wifiScanning, false);
    assert.equal(c.lastError, 'radio unavailable');

    c = setup();
    const ap = {ssid: 'Cafe: "$(example)"', isSecure: true, askingPassword: true};
    c.changePassword(ap, 'a $ literal "password"');
    c.connectToWifiNetwork(ap);
    assert.equal(c.calls.length, 1, 'duplicate connection blocked');
    assert.deepEqual(c.calls[0], ['nmcli', '--ask', 'dev', 'wifi', 'connect', ap.ssid]);
    assert.equal(c.input, 'a $ literal "password"\n');
    await settle();
    assert.equal(c.isUpdating, false);
    assert.equal(c.wifiConnectTarget, null);
    assert.equal(c.refreshes, 1, 'successful connection refreshes status');
    c.runAsync = () => Promise.reject('Secrets were required');
    c.connectToWifiNetwork(ap); await settle();
    assert.equal(c.isUpdating, false);
    assert.equal(ap.askingPassword, true);
    assert.equal(c.lastError, 'Secrets were required');
    c.active = ap;
    c.runAsync = command => { c.calls.push(Array.from(command)); return Promise.resolve(''); };
    c.disconnectWifiNetwork(); await settle();
    assert.equal(c.refreshes, 3, 'disconnect refreshes status without missing process id');

    for (const source of [wifi, bluetooth]) {
        c = vm.createContext({}); c.root = c;
        const a = {active: false, strength: 20, connected: false, paired: true, name: 'A'};
        const b = {active: true, strength: 80, connected: true, paired: true, name: 'B'};
        const isWifi = source === wifi;
        const rows = [];
        c.deviceListModel = {
            get count() { return rows.length; }, get(i) { return rows[i]; },
            remove(i) { rows.splice(i, 1); }, insert(i, row) { rows.splice(i, 0, row); },
            move(from, to) { rows.splice(to, 0, rows.splice(from, 1)[0]); }
        };
        const list = isWifi ? 'friendlyWifiNetworks' : 'friendlyDeviceList';
        c[isWifi ? 'wifiNetworks' : 'devices'] = [a, b];
        c[list] = []; c.updateActive = () => {};
        load(source, 'updateFriendlyList', c);
        c.updateFriendlyList(); const first = c[list];
        assert.equal(first[0], b, 'connected device/network sorts first');
        c.updateFriendlyList();
        assert.equal(c[list], first, 'unchanged ordering preserves model identity');
        if (isWifi) { b.active = false; a.strength = 100; }
        else { b.connected = false; a.connected = true; }
        c.updateFriendlyList();
        assert.equal(c[list][0], a, 'changed status updates ordering');
    }
    console.log('PASS: scan guards, power sequencing, connection success/failure, literal credentials, disconnect refresh, stable list identity and reordering');
})().catch(error => { console.error(error); process.exitCode = 1; });
