# AULA SC580 vendor HID protocol

Reverse-engineered from `AULA_SC580_Software.exe` (Inno Setup 5.3.3 installer →
`app/CBMouse.exe`, 32-bit MFC, PDB path `\Mouse\Debug\CBMouse.pdb`, built
2024-09-06). `CBMouse.exe` is a generic "CompX/CB" mouse configurator; the
device-specific bits live in `app/device/mouse/sc580/MS.ini`, which selects
`Protocol=3` → class `CDevDM`. Addresses below are in `CBMouse.exe` as loaded
at image base `0x400000` (Ghidra 11.3.2 headless, `analyzeHeadless`).

Legend: **[proven]** = read directly from the decompiled/disassembled code or
the shipped ini; **[inferred]** = consistent with the code but not confirmed
on hardware. Framing, checksum and the `0x30` reply have been confirmed on a real SC580
(wired); the setters have not been exercised yet.

## 1. Device identity  [proven — MS.ini]

| | VID | PID |
|---|---|---|
| wired (USB-C) | `0x088D` | `0x062E` |
| 2.4 GHz receiver | `0x089D` | `0x062F` |

* Sensor: `Sensor=0x3311` (PixArt PAW3311). DPI 200–12000 (see §5).
* `Identify=4d,31,33,37` → reply to cmd `0x30` starts with ASCII `M137`.
* `KeyCount=6`, `DpiNum=6`, `UsbRate=125,250,500,1000`, `DefaultRate=0x500`,
  `DebounceUI=4,6,8,…,20`, `DefSleepTime=6`, `ShowLED=0`, `ShowDpiColor=0`
  (lighting UI is hidden for this model).

The configurator opens the HID interface whose top-level collection has
**usage page `0xFF02`, usage `0x0000`**, with 33-byte input and output reports
(`CDevDM::FindHIDDevice` @ `0x004571c0`; the device-table fields compared are
usage page, usage, VID, PID and both report lengths `0x21`). On Linux that is
the `hidrawN` whose `report_descriptor` contains `06 02 FF`.

## 2. Transport  [proven]

* Host → mouse: `WriteFile(hDev, buf, 0x21)` — `CHidDev::WriteEP` @ `0x00456720`.
  `buf[0]` is the HID report ID (always `0`), `buf[1..32]` is the 32-byte payload.
  On Linux: `write(fd, b"\x00" + payload)`.
* Mouse → host: `ReadFile(hDev, buf, 0x21)` on the same interface — `ReadEP`
  @ `0x00456870`, and continuously by `DM_ServiceThread` @ `0x00456ad0`.
  On Linux `read()` returns the 32-byte payload (no report-ID byte because the
  descriptor has no numbered reports); `sc580ctl` tolerates both.
* `HidD_SetFeature`/`GetFeature` are imported (`0x0045a540`/`0x0045a710`) but
  are only used by the other protocol class (`CDevSprime`, protocols 1–2), not
  by the SC580.

## 3. Packet framing  [proven — `CDevDM::SendOne` @ `0x00457ba0`, `SendAndGet` @ `0x00457960`]

32-byte payload:

| offset | meaning |
|---|---|
| 0 | command id |
| 1 | `0` (status in replies) |
| 2 | `(nPackages & 0x0F) \| (packageIndex << 4)` — `0x01` for single-packet commands |
| 3 | data length `n` (0…27) |
| 4 … 30 | data (zero padded) |
| 31 | checksum = `sum(payload[4..30]) & 0xFF` (the loop at `0x00457ba0` adds bytes 4,5,6 / 7,8,9 / … / 28,29,30) |

Reply (same framing): byte 0 echoes the command, byte 1 is the status
(`CDevDM::WaitNotify` @ `0x00456de0`):

| status | meaning | app behaviour |
|---|---|---|
| `0` | OK | copy `payload[4..30]` to caller |
| `1` | busy | sleep 300 ms, resend (max 3) |
| `2` | offline (mouse asleep / out of range of the dongle) | give up, mark offline |
| `3` | data error | sleep 100 ms, resend (max 3) |

The app writes, sleeps 20 ms, then reads until a reply with a matching command
byte arrives (unmatched replies are skipped, up to 10 times).

Multi-packet commands (`SetMatrix` @ `0x00458200`, `SetMacro`/`AccessData`
@ `0x00457f60`) split the blob into 27-byte chunks, `nPackages = ceil(len/27)`,
`packageIndex = 0, 1, …`, and wait for the echo after each chunk.

## 4. Command table

All from `CDevDM::ApplySetting` @ `0x00458bd0` unless noted. The command byte
is loaded with `xor ecx,ecx ; lea ebx,[ecx+N]` right before `call 0x457ba0`,
which Ghidra drops — read from the disassembly.

| cmd | name | data (len) | notes |
|---|---|---|---|
| `0x01` | SetKey | `[matrixIndex, code0, code1, code2]` (4) | `FUN_004581a0`; matrix index = `K<n>` 4th field − 1 → buttons 1–6 are indices 0–5. 24-bit code little-endian, see §6. **[proven]** |
| `0x02` | SetRate | `[rateCode]` (1) | `1000 Hz→0x01, 500→0x02, 250→0x04, 125→0x08, 2000→0x10, 4000→0x20`. **[proven]** |
| `0x03` | SetDPI | 27 bytes: `[0]=0, [1]=(activeStage<<4)\|stageCount, [2+4i..3+4i]=X code LE, [4+4i..5+4i]=Y code LE` | Y code is `0` unless the ini enables separate X/Y DPI (SC580 doesn't). Active stage is 0-based. **[proven]** |
| `0x04` | SetDPIColor | 24 bytes: RGB × stage | DPI indicator colours; hidden for SC580 (`ShowDpiColor=0`). **[proven layout, inferred effect]** |
| `0x05` | SetLED | `[mode, (speed&0xF)\|(brightness<<4), …]` | mode-specific tail: 1 streaming `+[0]`; 2 breathing `+[n, rgb×n]`; 3 steady `+[r,g,b]`; 4 neon / 5 tail / 0 off: nothing; 6 colourful steady `+rgb×7`; 7 `+rgb×2`. Hidden for SC580 (`ShowLED=0`). **[proven layout]** |
| `0x06` | sensor params | `[lodIndex+1, angleSnap, ripple, 0, 0]` (5) | log string "Set sensor param failed". Fields identified by the sibling class's log lines `LOD=…`, `nAngleSnap=…`, `nRipple=…` @ `0x0045b2c0`. **[proven]** |
| `0x07` | wireless params | `[sleep, wakeOnMove, lightOffWhenMoving, debounce]` (4) | `sleep` = seconds/30 (UI 30 s…20 min → 1…40; default 6 = 3 min); `debounce` = ms (4…20, HW table == UI table because `DebounceHW` is absent). Log lines `nSleepTime=%d, nLightOFFWhenMoving=%d`, `nWakeUp=%d`. **[proven]** |
| `0x08` | SetMacro | multi-packet blob | `FUN_00457f60`; not implemented in sc580ctl. |
| `0x09` | SetMatrix | multi-packet, 3 bytes/key | all key codes at once; sc580ctl uses `0x01` per key instead (both paths exist in the app). **[proven]** |
| `0x0F` | Reset | `[0xFF]` (1) | factory reset; log "Reset". **[proven]** |
| `0x13` | GetDPI | none → reply `data[0] >> 4` = active stage (0-based) | `CDevDM::GetDPI` @ `0x004578b0`. **[proven]** |
| `0x30` | GetDeviceInfo | none → see below | used for identification and for battery polling (`CDevDM::GetPower` @ `0x004580b0`). **[proven]** |

`0x30` reply data (`PrivateSyncCfg` @ `0x00457660`, disassembly at `0x00457705` —
the `[esp+N]` loads index the whole data block). **Verified on hardware**
(2026-10-23, wired): `4d 31 33 37 01 16 11 aa 02 64 01`.

| data byte | meaning | live value |
|---|---|---|
| 0–3 | identity `M137` | `M137` |
| 4–5 | firmware, `data[4] \| data[5]<<8` ("nFw") | `0x1601` → 1.6.01 |
| 6 | sensor id → `GetSensor` @ `0x00417000` (`0x11→PAW3311`, `0x25→3325`, `0x35→3335`, `0x95→3395`) | `0x11` |
| 7 | unknown | `0xaa` |
| 8 | charge state: 0 on battery, 1 charging, 2 full (the app ships `battery_null/charging/full.png`) | `2` (on cable) |
| 9 | battery % | `100` |
| 10 | online flag (mouse awake and linked) | `1` |

The app sends everything in this order on "Apply": keys (`0x01` ×6 or
`0x09`), 50 ms, `0x03`, 50 ms, `0x04`, 50 ms, `0x05`, 50 ms, `0x02`, 50 ms,
`0x06`, 50 ms, `0x07`, [`0x0F`].

## 5. DPI codes  [proven — sensor table builder `FUN_00414f70` @ `0x00414f70`]

For sensor `0x3311` the app builds a table `dpi = 200, 300, …, 12000` with
`code = index + 1`, i.e. **`code = dpi / 100 − 1`** (800 → 7, 1600 → 15,
12000 → 119). Values that are not multiples of 100 are not in the table and
would be sent as code 0, so `sc580ctl` rejects them even though
`DPIRANGE=50,10000,50,…` in the ini suggests 50-DPI steps in the slider.

## 6. Key codes  [proven — `keyinfo_to_hardware_code` @ `0x0045aa70`, names @ `0x00420470` / menu @ `0x00422ad0`]

24-bit little-endian value; the low byte is the class.

| class | layout | examples |
|---|---|---|
| `0x20` mouse button | `btnMask<<8 \| 0x20` | left `0x000120`, right `0x000220`, middle `0x000420`, back `0x000820`, forward `0x001020` |
| `0x21`/`0x40` special | | triple click `0x033240` |
| `0x30` wheel | `delta<<8 \| 0x30` | scroll up `0x000130`, scroll down `0x00FF30` |
| `0x50` DPI | | loop `0x000150`, + `0x000250`, − `0x000350` |
| `0x70` misc | | disable `0x000070`, RGB on/off `0x000170`, effect switch `0x000470` (`0x000270` is an option hidden behind an ini flag) |
| `0x80` keyboard | `keycode<<16 \| modifiers<<8 \| 0x80`, HID usage ids, mods `ctrl=1 shift=2 alt=4 gui=8` | copy `0x060180`, Alt+F4 `0x3D0480`, Win+L `0x0F0880` |
| `0x90` consumer | `usage<<8 \| 0x90` | play/pause `0x00CD90`, mute `0x00E290`, calculator `0x019290` |
| `0xA0` macro | `count<<16 \| (mode\|slot)<<8 \| 0xA0`, mode `0x20` repeat n / `0x10` until released / `0x40` until any key | needs `0x08` first |

Defaults from `MS.ini [KEY]`: K1 left, K2 right, K3 middle, K4 forward,
K5 back, K6 DPI loop (`08,AA`).

## 7. Unsolicited input reports  [proven — `CHidDev::OnPop` @ `0x00456c90`]

Sent on the same interface at any time:

| payload[0] | payload[1] | payload[2] | payload[3] |
|---|---|---|---|
| `0xD2` DPI changed | `(stage0 << 4)` — app shows `(b>>4)+1` | | |
| `0xD1` power/link | online | battery % | charging |

`0xFF` in byte 0 is synthesised by the app itself when the handle dies.

## 8. Things still unverified on hardware

* Whether the receiver answers `0x30`/`0x13` while the mouse sleeps (expected
  status `2`), and how long after wake-up it starts answering.
* `0x30` data byte 7 (`0xaa`), and whether charge state `2` really means "full"
  rather than "wired".
* `0x04`/`0x05` do anything on an SC580 (the vendor UI hides them; the SC580X
  variant may have lighting).
* LOD index→mm mapping (`LodUI`/`LodHW` are commented out in `MS.ini`);
  `sc580ctl` sends index 0 (`data[0]=1`) unless told otherwise.
