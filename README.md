# AULA SC580 for Omarchy

Configure the **AULA SC580 / SC580X** tri-mode gaming mouse from the Omarchy
bar — no Windows software, no vendor driver. A Quickshell bar widget shows the
mouse's battery and opens a panel for everything the Windows app exposes;
a small CLI (`sc580ctl`) does the same from the terminal.

The mouse speaks a vendor HID protocol that was reverse-engineered from
`AULA_SC580_Software.exe`; the write-up with evidence is in
[PROTOCOL.md](PROTOCOL.md).

## What you get

**In the bar:** a mouse icon — with the battery percentage when you're on the
2.4 GHz receiver — that dims when the mouse isn't connected. Left-click opens
the panel, right-click refreshes.

**In the panel:**

| Section | What it does |
|---|---|
| Header | link type (wired / 2.4G), battery %, charging/full, and the active DPI in big digits |
| DPI stages | 1–6 stages; click a stage to switch to it, drag the slider to change its value (200–12 000, steps of 100), `+`/`−` to add or remove stages |
| Polling rate | 125 / 250 / 500 / 1000 Hz |
| Power | sleep timer (30 s – 20 min), wake-up-on-move |
| Buttons | remap all six buttons (left, right, middle, forward, back, DPI) to any built-in function — or **capture a keyboard shortcut**: pick "Keyboard shortcut…", click the field, press the combination |
| Advanced | click debounce (4–20 ms), angle snapping, ripple control |
| Footer | *Push all settings* (re-sends everything, e.g. after a reset) and *Factory reset* (press twice) |

Settings are saved on the mouse itself (they survive reboots and work on any
computer) **and** in `~/.config/sc580/config.json`, because the mouse cannot be
asked what it is set to — the vendor app keeps a copy on disk for the same
reason.

## Requirements

* Omarchy with the Quickshell shell (`omarchy plugin …` commands available).
* `python3` (always present on Omarchy; the driver uses only the standard library).
* Read/write access to the mouse's `hidraw` device — a one-time udev rule, see
  below. This is the only step that needs root.

Works wired (USB-C, `088d:062e`) and through the 2.4 GHz receiver
(`089d:062f`). Bluetooth mode is **not** configurable (the mouse only exposes
the vendor interface over USB/2.4G — same limitation as the Windows app).

## Install

### From Omarchy (recommended)

```sh
omarchy plugin add https://github.com/crucialjun/omarchy-sc580 --enable
```

Pick the bar section when asked (right is a good spot). Open the panel: if it
says *permission denied*, click **Grant device access** — Omarchy's polkit
dialog asks for your password once, the udev rule is installed, and the mouse
shows up (replug it if it doesn't within a second or two).

That's the whole install; the driver ships inside the plugin folder.

### Manually / without the marketplace

```sh
git clone https://github.com/crucialjun/omarchy-sc580 ~/src/omarchy-sc580
cd ~/src/omarchy-sc580
./install.sh            # sc580ctl → ~/.local/bin, udev rule (sudo), plugin → ~/.config/omarchy/plugins
```

`./install.sh --no-plugin` installs just the CLI and udev rule on any Linux.

### Hyprland tip

Have the mouse pick up your stored settings at login, in case it was factory
reset or used on another machine:

```ini
# ~/.config/hypr/autostart.conf
exec-once = sc580ctl apply
```

## Remove

```sh
omarchy plugin remove io.github.crucialjun.aula-sc580   # the widget + bundled driver
rm -rf ~/.config/sc580                                   # stored settings (optional)
sudo rm /etc/udev/rules.d/70-aula-sc580.rules            # device permission rule (optional)
rm -f ~/.local/bin/sc580ctl                              # only if you ran install.sh
```

Removing the plugin does not change anything on the mouse; whatever you last
set stays until you change it again (or `sc580ctl reset`).

## Using the panel

* **Switching DPI** from the mouse's own DPI button is reflected in the panel
  within a few seconds (and immediately in `sc580ctl watch`).
* **Keyboard shortcuts on buttons** are stored in the mouse as a real HID
  keyboard combo, so they work in every app and on every OS. Captured keys:
  letters, digits, F1–F24, arrows, Enter/Tab/Space/Backspace,
  Home/End/PgUp/PgDn/Insert/Delete, punctuation, with any of Ctrl/Shift/Alt/Super.
  Combos that Hyprland has bound globally (most `Super+…`) are swallowed by the
  compositor before the panel sees them — set those from the terminal:
  `sc580ctl key 4 kbd:super+e`.
* At least one button must stay **Left click**; the panel and CLI refuse to
  remove the last one (so does the vendor app).
* **Not connected** in the header means no SC580 interface was found: the mouse
  is off, in Bluetooth mode, or the receiver isn't plugged in. Settings you
  change while disconnected are saved and pushed with *Push all settings*.
* **Asleep / out of range**: the receiver is present but the mouse isn't
  talking to it. Move the mouse and try again.

## The CLI

`sc580ctl` lives in the plugin folder (`~/.config/omarchy/plugins/io.github.crucialjun.aula-sc580/bin/sc580ctl`)
and is put on your `PATH` by `install.sh`.

```
sc580ctl status [--json]          connection, battery, active DPI, stored config
sc580ctl info                     raw device-info reply (identity, firmware, sensor)
sc580ctl dpi stage 3              switch to stage 3
sc580ctl dpi set 3 2400           set stage 3 to 2400 DPI (200–12000, steps of 100)
sc580ctl dpi stages 800,1600,3200 replace the list (1–6 stages)
sc580ctl dpi remove 6
sc580ctl rate 1000                125 | 250 | 500 | 1000
sc580ctl keys                     list buttons and functions
sc580ctl key 6 dpi_up             remap button 1–6
sc580ctl key 4 kbd:alt+left       keyboard combo (ctrl/shift/alt/super + key)
sc580ctl sleep 300                30 60 90 120 180 240 300 600 900 1200 seconds
sc580ctl debounce 8               4…20 ms
sc580ctl set wake-on-move off     also: light-off-moving, angle-snap, ripple, lod 1|2
sc580ctl apply                    push the whole stored config
sc580ctl reset                    factory reset the mouse and the stored config
sc580ctl watch                    JSON lines: {"event":"dpi","stage":3} / {"event":"power",...}
sc580ctl --dry-run …              print the packets instead of sending
sc580ctl -v …                     hex-dump the traffic on stderr
```

Every setter writes `~/.config/sc580/config.json` and then pushes just that
change; `--no-push` only updates the file.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Panel says *permission denied* | click **Grant device access**, or `sudo install -m644 udev/70-aula-sc580.rules /etc/udev/rules.d/ && sudo udevadm control --reload-rules && sudo udevadm trigger`, then replug |
| Widget not in the bar | `omarchy plugin enable io.github.crucialjun.aula-sc580 --section right`; after editing plugin files, `omarchy-shell shell rescanPlugins` or `omarchy restart shell` |
| *Could not run bin/sc580ctl* | `python3` missing, or the plugin folder was moved |
| A setting "didn't take" | `sc580ctl -v …` shows the request/reply; status byte `1` = busy (retry), `2` = mouse asleep, `3` = the mouse rejected the data — please open an issue with the dump |
| Identity isn't `M137` | not an SC580 firmware this was tested with — open an issue with `sc580ctl info` |

## Privacy & safety

The plugin talks only to the mouse's hidraw device and runs no network code.
The udev rule grants the logged-in user access to exactly two USB IDs. The
only privileged action is installing that rule (via `pkexec` from the panel or
`sudo` in `install.sh`). Nothing outside `~/.config/sc580`,
`~/.config/omarchy/plugins/<id>` and (optionally) `~/.local/bin/sc580ctl` is
written.

## Development

```
manifest.json, Panel.qml, Model.js   the Omarchy plugin (repo root = plugin root)
bin/sc580ctl                         driver + CLI, Python 3 stdlib
udev/70-aula-sc580.rules
tests/test_protocol.py               packet encoding/parsing against a fake device  (python3 -I tests/test_protocol.py)
PROTOCOL.md                          the reverse-engineered protocol with addresses in CBMouse.exe
install.sh                           offline installer
MARKETPLACE.md                       how this is published to plugins.omarchy.org
```

Verified on hardware: SC580, firmware 1.6.01, PAW3311, wired (identity,
battery, DPI query). Setters follow the vendor app byte-for-byte and are
unit-tested; please report anything that misbehaves with a `-v` dump.

## License

MIT — see [LICENSE](LICENSE). AULA and SC580 are trademarks of their owner;
this project is independent and not affiliated with AULA.
