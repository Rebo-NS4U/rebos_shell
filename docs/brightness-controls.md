# Brightness and percentage controls

Brightness requests from the shell and IPC snap to 5% ticks, with a 5% minimum
and a 100% maximum. Dashboard brightness, speaker volume, microphone volume,
application mixer volume, shadow opacity, gradient center positions and halftone
start/end percentage sliders snap while dragging and scrolling. Audio and
appearance sliders retain their existing minimums. Time, angle and size controls
retain their existing precision.

## AMD backlight jump workaround

On one AU Optronics B160UAK01.L panel using amdgpu with Linux 7.2.11, a brightness
sweep reproduced a sharp jump near 91% of the raw backlight range. The kernel
reported `Using custom brightness curve`. This is separate from slider stepping.

The optional [module configuration](hardware/amdgpu-brightness-fix.conf) sets
`amdgpu dcdebugmask=0x40000`, disabling the firmware's custom brightness curve.
The [AMD driver definition](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/amd/include/amd_shared.h)
names this bit `DC_DISABLE_CUSTOM_BRIGHTNESS_CURVE`.

Apply this only on affected AMD systems after checking support in the installed
kernel. If an existing `dcdebugmask` is configured, preserve its bits and add
`0x40000` rather than replacing them. An administrator can install the example as
`/etc/modprobe.d/amdgpu-brightness-fix.conf`, rebuild the initramfs (on Arch,
`mkinitcpio -P`), then reboot when convenient. The shell never installs this
system setting automatically. Verify the mask and test brightness after reboot;
slider snapping alone does not verify the driver workaround.

To undo the workaround, remove this configuration, restore any previous mask,
rebuild the initramfs and reboot.
