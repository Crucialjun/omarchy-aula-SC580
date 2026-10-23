// Pure helpers for the SC580 panel. Mirrors the tables in bin/sc580ctl so the
// QML never has to guess what the CLI accepts.

var RATES = [125, 250, 500, 1000]
var DPI_MIN = 200
var DPI_MAX = 12000
var DPI_STEP = 100
var MAX_STAGES = 6
var DEBOUNCE_MS = [4, 6, 8, 10, 12, 14, 16, 18, 20]
var SLEEP_SECONDS = [30, 60, 90, 120, 180, 240, 300, 600, 900, 1200]

var BUTTONS = [
  { id: 1, label: "Left" },
  { id: 2, label: "Right" },
  { id: 3, label: "Middle" },
  { id: 4, label: "Forward" },
  { id: 5, label: "Back" },
  { id: 6, label: "DPI button" }
]

// value = what sc580ctl key <n> <value> accepts; label = what we render.
var KEY_FUNCTIONS = [
  { value: "custom", label: "Keyboard shortcut…" },
  { value: "left", label: "Left click" },
  { value: "right", label: "Right click" },
  { value: "middle", label: "Middle click" },
  { value: "forward", label: "Forward" },
  { value: "back", label: "Back" },
  { value: "scroll_up", label: "Scroll up" },
  { value: "scroll_down", label: "Scroll down" },
  { value: "triple_click", label: "Triple click" },
  { value: "dpi_loop", label: "DPI loop" },
  { value: "dpi_up", label: "DPI +" },
  { value: "dpi_down", label: "DPI −" },
  { value: "play_pause", label: "Play / pause" },
  { value: "next_track", label: "Next track" },
  { value: "prev_track", label: "Previous track" },
  { value: "volume_up", label: "Volume +" },
  { value: "volume_down", label: "Volume −" },
  { value: "mute", label: "Mute" },
  { value: "copy", label: "Copy (Ctrl+C)" },
  { value: "paste", label: "Paste (Ctrl+V)" },
  { value: "undo", label: "Undo (Ctrl+Z)" },
  { value: "close_window", label: "Close window (Alt+F4)" },
  { value: "show_desktop", label: "Show desktop (Super+D)" },
  { value: "lock_screen", label: "Lock (Super+L)" },
  { value: "disable", label: "Disabled" }
]
var CUSTOM = "custom"
var MODS = ["ctrl", "shift", "alt", "super"]
var MOD_ALIASES = { control: "ctrl", win: "super", meta: "super", cmd: "super", option: "alt" }

function isShortcut(v) { return typeof v === "string" && v.indexOf("kbd:") === 0 }
function shortcutText(v) { return isShortcut(v) ? v.slice(4) : "" }

// "Ctrl + Shift+T" -> "kbd:ctrl+shift+t"; null when there is no key.
// sc580ctl does the authoritative validation (unknown key names error out).
function normalizeShortcut(text) {
  var parts = String(text || "").toLowerCase().replace(/\s+/g, "").split("+").filter(function (p) { return p !== "" })
  if (parts.length === 0) return null
  var mods = [], key = null
  for (var i = 0; i < parts.length; i++) {
    var p = MOD_ALIASES[parts[i]] || parts[i]
    if (MODS.indexOf(p) >= 0) { if (mods.indexOf(p) < 0) mods.push(p) }
    else if (key === null) key = p
    else return null
  }
  if (key === null) return null
  return "kbd:" + mods.concat([key]).join("+")
}

function sleepLabel(seconds) {
  var s = Number(seconds)
  if (s < 60) return s + " s"
  var m = s / 60
  return (m === Math.floor(m) ? m : m.toFixed(1)) + " min"
}

function sleepOptions() {
  return SLEEP_SECONDS.map(function (s) { return { value: String(s), label: sleepLabel(s) } })
}

function debounceOptions() {
  return DEBOUNCE_MS.map(function (ms) { return { value: String(ms), label: ms + " ms" } })
}

function keyOptions(current) {
  var opts = KEY_FUNCTIONS.slice()
  // The assigned shortcut (or a raw 0x… code set from the CLI) shows as its own row.
  if (current && !opts.some(function (o) { return o.value === current }))
    opts.push({ value: current, label: isShortcut(current) ? "Shortcut: " + shortcutText(current) : current })
  return opts
}

function keyLabel(value) {
  for (var i = 0; i < KEY_FUNCTIONS.length; i++)
    if (KEY_FUNCTIONS[i].value === value) return KEY_FUNCTIONS[i].label
  return value || "—"
}

function clampDpi(v) {
  var n = Math.round(Number(v) / DPI_STEP) * DPI_STEP
  return Math.max(DPI_MIN, Math.min(DPI_MAX, n))
}

function parseStatus(text) {
  try {
    var s = JSON.parse(String(text || "").trim())
    return (s && typeof s === "object") ? s : null
  } catch (e) {
    return null
  }
}

function batteryIcon(status) {
  if (!status || !status.connected) return "󰍾"          // mouse-off
  var info = status.info || {}
  if (status.link === "wired") return "󰍽"
  if (info.online === false) return "󰍾"
  var pct = Number(info.battery)
  if (info.charging || info.full) return "󰂄"
  if (!isFinite(pct)) return "󰍽"
  if (pct >= 90) return "󰁹"
  if (pct >= 70) return "󰂁"
  if (pct >= 50) return "󰁿"
  if (pct >= 30) return "󰁽"
  if (pct >= 10) return "󰁻"
  return "󰂎"
}

function statusLine(status) {
  if (!status) return "NO DATA"
  if (!status.connected) return "NOT CONNECTED"
  var info = status.info || {}
  var parts = [status.link === "wired" ? "WIRED" : "2.4G WIRELESS"]
  if (info.online === false) parts.push("ASLEEP / OUT OF RANGE")
  else if (isFinite(Number(info.battery))) parts.push(info.battery + "%" + (info.charging ? " CHARGING" : (info.full ? " FULL" : "")))
  return parts.join(" · ")
}

// ---- key capture: Qt key codes -> the names sc580ctl's kbd: syntax accepts ----
var QT_KEY_NAMES = {
  0x01000004: "enter", 0x01000005: "enter", 0x01000000: "esc", 0x01000001: "tab", 0x01000002: "tab",
  0x01000003: "backspace", 0x20: "space", 0x01000006: "insert", 0x01000007: "delete",
  0x01000010: "home", 0x01000011: "end", 0x01000012: "left", 0x01000013: "up", 0x01000014: "right",
  0x01000015: "down", 0x01000016: "pageup", 0x01000017: "pagedown", 0x01000024: "capslock",
  0x01000025: "numlock", 0x01000026: "scrolllock", 0x01000009: "printscreen", 0x01000008: "pause",
  0x2d: "minus", 0x3d: "equal", 0x5b: "lbracket", 0x5d: "rbracket", 0x5c: "backslash",
  0x3b: "semicolon", 0x27: "quote", 0x60: "grave", 0x2c: "comma", 0x2e: "period", 0x2f: "slash",
  // shifted US symbols map back to their physical key
  0x21: "1", 0x40: "2", 0x23: "3", 0x24: "4", 0x25: "5", 0x5e: "6", 0x26: "7", 0x2a: "8", 0x28: "9", 0x29: "0",
  0x5f: "minus", 0x2b: "equal", 0x7b: "lbracket", 0x7d: "rbracket", 0x7c: "backslash",
  0x3a: "semicolon", 0x22: "quote", 0x7e: "grave", 0x3c: "comma", 0x3e: "period", 0x3f: "slash"
}
var QT_MODIFIER_KEYS = [0x01000020, 0x01000021, 0x01000022, 0x01000023, 0x01000053, 0x01000054, 0x01001103]

function isModifierKey(key) { return QT_MODIFIER_KEYS.indexOf(key) >= 0 }

function keyNameFromQt(key) {
  if (key >= 0x41 && key <= 0x5a) return String.fromCharCode(key).toLowerCase()      // A-Z
  if (key >= 0x30 && key <= 0x39) return String.fromCharCode(key)                    // 0-9
  if (key >= 0x01000030 && key <= 0x01000047) return "f" + (key - 0x01000030 + 1)    // F1-F24
  return QT_KEY_NAMES[key] || null
}

function modsFromQt(modifiers) {
  var m = []
  if (modifiers & Qt.ControlModifier) m.push("ctrl")
  if (modifiers & Qt.ShiftModifier) m.push("shift")
  if (modifiers & Qt.AltModifier) m.push("alt")
  if (modifiers & Qt.MetaModifier) m.push("super")
  return m
}

// A key event -> "kbd:ctrl+shift+t", or null while only modifiers are down.
function shortcutFromEvent(key, modifiers) {
  if (isModifierKey(key)) return null
  var name = keyNameFromQt(key)
  if (!name) return null
  return "kbd:" + modsFromQt(modifiers).concat([name]).join("+")
}

function prettyShortcut(spec) {
  return shortcutText(spec).split("+").map(function (p) {
    return { ctrl: "Ctrl", shift: "Shift", alt: "Alt", super: "Super", esc: "Esc", enter: "Enter" }[p] || (p.length === 1 ? p.toUpperCase() : p)
  }).join(" + ")
}

function modifierFlagForKey(key) {
  if (key === 0x01000021) return Qt.ControlModifier
  if (key === 0x01000020) return Qt.ShiftModifier
  if (key === 0x01000023) return Qt.AltModifier
  if (key === 0x01000022) return Qt.MetaModifier
  return 0
}
