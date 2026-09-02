import QtQuick
import Quickshell
import Quickshell.Io

// Settings service for pointer/mouse configuration. All state lives in
// Hyprland; this service reads it with `hyprctl getoption -j` and writes it
// with `hyprctl eval`. Nothing is persisted by the plugin — values apply
// immediately and live for the session, exactly like `hyprctl`.
//
// Hardening (marketplace review): producer output is bounded in bytes,
// device and name counts are capped, each Process has a hard watchdog timer
// that kills a hung child and recovers the queue, and external strings
// (device names) are length-capped here and rendered as PlainText in the UI.
Item {
  id: root
  visible: false

  property var settings: ({})

  // ----------------------------------------------------------- hard limits
  // A single getoption/device record is a few hundred bytes; 256 KiB is far
  // beyond anything hyprctl legitimately emits while still tiny enough to
  // refuse a runaway producer. 8s is generous for a local IPC call.
  readonly property int maxBytes: 256 * 1024
  readonly property int watchdogMs: 8000
  readonly property int maxDevices: 64
  readonly property int maxNameLength: 256
  readonly property int queueDepth: 32

  // ------------------------------------------------------- global options
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
    "input:touchpad:natural_scroll": false,
    "input:touchpad:scroll_factor": 0.4,
    "input:touchpad:disable_while_typing": true,
    "input:touchpad:tap-to-click": false,
    "input:touchpad:drag_lock": false
  })

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
  // [{ name, scrollFactor, defaultSpeed }] — name already length-capped.
  property var devices: []

  property bool busy: false
  property string lastError: ""

  // ------------------------------------------------------------- read path
  Process {
    id: readProc
    property string _key: ""
    stdout: StdioCollector {
      onStreamFinished: root._applyRead(readProc._key, root._bounded(text))
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.lastError === "")
        root.lastError = "read failed: " + readProc._key
      readWatch.stop()
      root._readNext()
    }
  }
  Timer {
    id: readWatch
    interval: root.watchdogMs
    repeat: false
    onTriggered: {
      readProc.running = false   // hard kill of a hung hyprctl
      root.lastError = "watchdog: read " + readProc._key
      root._readNext()           // recover the queue
    }
  }

  // ------------------------------------------------------------ write path
  Process {
    id: writeProc
    property string _cmd: ""
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.lastError === "")
        root.lastError = "write failed"
      writeWatch.stop()
      root._writeNext()
    }
  }
  Timer {
    id: writeWatch
    interval: root.watchdogMs
    repeat: false
    onTriggered: {
      writeProc.running = false
      root.lastError = "watchdog: write"
      root._writeNext()
    }
  }

  // ---------------------------------------------------------- devices read
  Process {
    id: devProc
    command: ["hyprctl", "devices", "-j"]
    stdout: StdioCollector {
      onStreamFinished: root._applyDevices(root._bounded(text))
    }
    onExited: function() {
      devWatch.stop()
      root.busy = false
    }
  }
  Timer {
    id: devWatch
    interval: root.watchdogMs
    repeat: false
    onTriggered: {
      devProc.running = false
      root.lastError = "watchdog: devices"
      root.busy = false
    }
  }

  property var _readQueue: []
  property var _writeQueue: []

  // Truncate a producer buffer to the byte cap before parsing. A huge or
  // endlessly-growing hyprctl response is bounded before any JSON.parse.
  function _bounded(text) {
    if (!text) return ""
    if (text.length > maxBytes) {
      lastError = "output exceeded " + maxBytes + " bytes"
      return text.substring(0, maxBytes)
    }
    return text
  }

  function _applyRead(key, text) {
    if (!key || !text) return
    try {
      var obj = JSON.parse(text)
      var next = Object.assign({}, options)
      var v = obj["float"] !== undefined ? obj["float"]
            : obj["int"] !== undefined ? obj["int"]
            : obj["str"] !== undefined ? obj["str"]
            : options[key]
      next[key] = v
      options = next
    } catch (e) {
      lastError = "parse: " + key
    }
  }

  function _applyDevices(text) {
    if (!text) { busy = false; return }
    try {
      var obj = JSON.parse(text)
      var mice = obj.mice || []
      var list = []
      // Cap the device count so a hostile or corrupted device dump cannot
      // flood the model; cap each name so rendering stays bounded too.
      var count = Math.min(mice.length, maxDevices)
      for (var i = 0; i < count; i++) {
        var m = mice[i]
        var name = String(m.name || "")
        if (name.length > maxNameLength) name = name.substring(0, maxNameLength)
        list.push({
          name: name,
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
    readWatch.restart()
    readProc.running = true
  }

  function _writeNext() {
    if (_writeQueue.length === 0) { refreshDevices(); return }
    var cmd = _writeQueue.shift()
    writeProc._cmd = cmd
    writeProc.command = ["bash", "-c", cmd]
    writeWatch.restart()
    writeProc.running = true
  }

  // ------------------------------------------------------------- public
  function refresh() {
    var keys = globalKeys.concat(touchpadKeys)
    if (keys.length > queueDepth) keys = keys.slice(0, queueDepth)
    _readQueue = keys.slice()
    if (!readProc.running) _readNext()
    else busy = true
  }

  function refreshDevices() {
    if (!devProc.running) {
      busy = true
      devWatch.restart()
      devProc.running = true
    }
  }

  // hyprctl keyword is disabled on Omarchy (Lua config, not the legacy
  // parser), so writes go through `hyprctl eval` with hl.config / hl.device.
  function set(name, value) {
    _enqueueWrite("hyprctl eval " + _q(_configLua(name, value)))
    var next = Object.assign({}, options)
    next[name] = value
    options = next
  }

  function setDeviceScrollFactor(deviceName, factor) {
    var lua = "hl.device({ name = " + _luaString(deviceName)
        + ", scroll_factor = " + Number(factor) + " })"
    _enqueueWrite("hyprctl eval " + _q(lua))
    var list = devices.slice()
    for (var i = 0; i < list.length; i++)
      if (list[i].name === deviceName)
        list[i] = Object.assign({}, list[i], { scrollFactor: Number(factor) })
    devices = list
  }

  function _enqueueWrite(cmd) {
    // Drop the oldest queued write if a burst of slider moves overruns the
    // queue; the latest value always wins once the writer drains.
    if (_writeQueue.length >= queueDepth) _writeQueue.shift()
    _writeQueue.push(cmd)
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
