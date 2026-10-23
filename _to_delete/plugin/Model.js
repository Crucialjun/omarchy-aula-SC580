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
