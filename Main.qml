import QtQuick
import Quickshell
import Quickshell.Io

// Settings service for pointer/mouse configuration. All state lives in
// Hyprland; this service reads it with `hyprctl getoption -j` and writes it
// with `hyprctl keyword`. Nothing is persisted by the plugin itself — values
// apply immediately and live for the session, exactly like `hyprctl keyword`.
//
// Two kinds of state:
//   - global input options (scroll_factor, sensitivity, accel_profile, ...)
//   - the list of pointer devices and their per-device scroll factor
Item {
  id: root
  visible: false

  property var settings: ({})

  // ------------------------------------------------------- global options
  // Each entry: { key, value, set }. `set` mirrors hyprctl's "set" flag —
  // false means the value is the compiled-in default rather than an override.
  property var options: ({
    "input:scroll_factor": 1.0,
    "input:sensitivity": 0.0,
    "input:accel_profile": "adaptive",
    "input:natural_scroll": false,
    "input:left_handed": false,
    "input:scroll_method": "2fg",
    "input:emulate_discrete_scroll": 1,
    "input:middle_button_paste": true,
    "input:follow_mouse": 1,
    "input:float_switch_override_focus": 0,
    "input:touchpad:natural_scroll": false,
    "input:touchpad:scroll_factor": 0.4,
    "input:touchpad:disable_while_typing": true,
    "input:touchpad:tap-to-click": false,
    "input:touchpad:drag_lock": false
  })

  // Which option keys the panel shows, in order. The service reads whatever
  // is in `options`; this is only the display contract.
  readonly property var globalKeys: [
    "input:scroll_factor",
    "input:sensitivity",
    "input:accel_profile",
    "input:left_handed",
    "input:natural_scroll",
    "input:scroll_method",
    "input:emulate_discrete_scroll",
    "input:middle_button_paste",
    "input:follow_mouse"
  ]
  readonly property var touchpadKeys: [
    "input:touchpad:natural_scroll",
    "input:touchpad:scroll_factor",
    "input:touchpad:disable_while_typing",
    "input:touchpad:tap-to-click",
    "input:touchpad:drag_lock"
  ]

  // ------------------------------------------------------------- devices
  // [{ name, scrollFactor, defaultSpeed }]
  property var devices: []

  property bool busy: false
  property string lastError: ""

  // One Process per concern. hyprctl is fast; we serialize reads through a
  // small queue so a burst of slider moves never interleaves keyword calls.
  Process {
    id: readProc
    stdout: StdioCollector {
      onStreamFinished: root._applyRead(readProc._key, text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.lastError = "read failed: " + readProc._key
      root._readNext()
    }
    property string _key: ""
  }

  Process {
    id: writeProc
    onExited: function(exitCode) {
      if (exitCode !== 0) root.lastError = "write failed: " + writeProc._cmd
      root._writeNext()
    }
    property string _cmd: ""
  }

  Process {
    id: devProc
    command: ["hyprctl", "devices", "-j"]
    stdout: StdioCollector {
      onStreamFinished: root._applyDevices(text)
    }
    onExited: root.busy = false
  }

  property var _readQueue: []
  property var _writeQueue: []

  function _applyRead(key, text) {
    if (!key) return
    try {
      var obj = JSON.parse(text)
      var next = Object.assign({}, options)
      // getoption -j returns { option, str/int/float, set }
      var v = obj["float"] !== undefined ? obj["float"]
            : obj["int"] !== undefined ? obj["int"]
            : obj["str"] !== undefined ? obj["str"]
            : options[key]
      // Normalize numeric booleans that hyprctl reports as int 0/1.
      next[key] = v
      options = next
    } catch (e) {
      lastError = "parse: " + key
    }
  }

  function _applyDevices(text) {
    try {
      var obj = JSON.parse(text)
      var mice = obj.mice || []
      var list = []
      for (var i = 0; i < mice.length; i++) {
        var m = mice[i]
        list.push({
          name: String(m.name || ""),
          scrollFactor: m.scrollFactor !== undefined ? m.scrollFactor : -1,
          defaultSpeed: m.defaultSpeed !== undefined ? m.defaultSpeed : 0
        })
      }
      devices = list
    } catch (e) {
      lastError = "parse devices"
    }
  }

  function _readNext() {
    if (_readQueue.length === 0) { busy = false; return }
    busy = true
    var key = _readQueue.shift()
    readProc._key = key
    readProc.command = ["hyprctl", "getoption", key, "-j"]
    readProc.running = true
  }

  function _writeNext() {
    if (_writeQueue.length === 0) { refreshDevices(); return }
    var cmd = _writeQueue.shift()
    writeProc._cmd = cmd
    writeProc.command = ["bash", "-c", cmd]
    writeProc.running = true
  }

  // ------------------------------------------------------------- public
  function refresh() {
    _readQueue = globalKeys.concat(touchpadKeys).slice()
    if (!readProc.running) _readNext()
    else busy = true
  }

  function refreshDevices() {
    if (!devProc.running) { busy = true; devProc.running = true }
  }

  // hyprctl keyword is disabled on Omarchy (the config is Lua, not the legacy
  // parser), so writes go through `hyprctl eval` with an hl.config / hl.device
  // call. `name` is the full option path ("input:scroll_factor",
  // "input:touchpad:scroll_factor"); `value` is a typed JS value.
  function set(name, value) {
    _writeQueue.push("hyprctl eval " + _q(_configLua(name, value)))
    // Optimistic local update so the UI never waits on the process round-trip.
    var next = Object.assign({}, options)
    next[name] = value
    options = next
    if (!writeProc.running) _writeNext()
  }

  function setDeviceScrollFactor(deviceName, factor) {
    var lua = "hl.device({ name = " + _luaString(deviceName) + ", scroll_factor = " + Number(factor) + " })"
    _writeQueue.push("hyprctl eval " + _q(lua))
    var list = devices.slice()
    for (var i = 0; i < list.length; i++)
      if (list[i].name === deviceName) list[i] = Object.assign({}, list[i], { scrollFactor: Number(factor) })
    devices = list
    if (!writeProc.running) _writeNext()
  }

  // Build an hl.config call for a dotted option path. Splits "input:touchpad:x"
  // into nested tables and renders the value with the right Lua type.
  function _configLua(name, value) {
    var parts = String(name).split(":")
    var inner = _luaValue(value)
    for (var i = parts.length - 1; i >= 0; i--)
      inner = "{ " + parts[i] + " = " + inner + " }"
    return "hl.config(" + inner + ")"
  }

  function _luaValue(v) {
    if (v === true || v === false) return v ? "true" : "false"
    if (typeof v === "number") return String(v)
    var n = Number(v)
    if (v !== "" && !isNaN(n) && String(v).trim() !== "") return String(n)
    return _luaString(v)
  }

  function _luaString(s) { return '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"' }

  function _q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

  Component.onCompleted: refresh()
}
