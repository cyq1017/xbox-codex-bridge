# Xbox Logo Light Probe

This is an isolated, experimental USB probe for the Microsoft Xbox Series
Controller `045e:0b12`. It is not linked into XboxCodexBridge and does not
change the bridge mappings, Swift package, launch command, macOS driver, SIP,
or controller firmware.

The probe sends one fixed GIP LED packet: constant white, brightness `20/50`.
Its default behavior is dry-run only.

## Build and verify

```bash
brew install libusb
make test
./build/xbox-light-probe
```

Dry-run must print:

```text
packet: 0a 20 01 03 00 01 14
DRY RUN: no USB access performed
```

## One-shot hardware experiment

The execution path requires both an explicit acknowledgement flag and root:

```bash
sudo ./build/xbox-light-probe \
  --execute \
  --acknowledge-temporary-disconnect
```

During execution, libusb temporarily detaches the Apple Xbox driver, claims
interface `0`, finds its interrupt OUT endpoint, sends exactly seven bytes,
then releases the interface and asks macOS to restore the Apple driver. The
controller and XboxCodexBridge may disconnect briefly while macOS re-enumerates
the device.

If the controller does not reconnect, unplug and reconnect the USB cable. Do
not repeat the command until normal controller input has returned.

## Verified boundary

On 2026-07-18, the controller accepted the packet at its USB endpoint and the
Apple driver plus XboxCodexBridge automatically reconnected. Whether the Apple
driver immediately resets the visible Logo state must be confirmed by direct
visual observation on the physical controller.
