import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.alennumberoneai.mouse"
  ipcTarget: "io.github.alennumberoneai.mouse"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color surface: Color.popups.background
  readonly property color accent: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function num(key) { return Number(service.options[key]) }
  function boolOpt(key) { var v = service.options[key]; return v === true || v === 1 || v === "1" || v === "true" }
  function str(key) { return String(service.options[key]) }

  function fmt(v, digits) {
    var n = Number(v)
    if (isNaN(n)) return "0"
    return n.toFixed(digits === undefined ? 2 : digits)
  }

  // Acceleration profile is a free-form string in Hyprland ("flat", "adaptive",
  // or "custom ..."). We expose the two one-word profiles as presets.
  function accelIndex() { return str("input:accel_profile") === "flat" ? 1 : 0 }
  function scrollMethodIndex() {
    var m = str("input:scroll_method")
    var opts = ["2fg", "edge", "on_button_down", "no_scroll"]
    var i = opts.indexOf(m)
    return i < 0 ? 0 : i
  }
  function followMouseIndex() {
    var v = num("input:follow_mouse")
    return (v >= 0 && v <= 3) ? Math.round(v) : 1
  }

  visible: service.settings.showInBar !== false
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    service.refresh()
    service.refreshDevices()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Main {
    id: service
    settings: root.settings
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰍽"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) { service.refresh(); service.refreshDevices() }
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      Keys.onEscapePressed: root.close()
    }

    Flickable {
      id: panelFlick
      anchors.fill: parent
      contentWidth: width
      contentHeight: column.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: column
        width: panelFlick.width
        spacing: Style.spacing.md
        padding: Style.spacing.panelPadding

        // ------------------------------------------------------- header
        Row {
          spacing: Style.spacing.sm
          Text {
            text: "󰍽  Mouse"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
          }
          Item { width: 1; height: 1 }
          PanelActionButton {
            iconText: "󰑐"
            foreground: root.foreground
            enabled: !service.busy
            onClicked: { service.refresh(); service.refreshDevices() }
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        // ------------------------------------------------ pointer section
        PanelSectionHeader { text: "Pointer" }

        // Scroll speed (mouse wheel)
        Column {
          width: parent.width - Style.spacing.panelPadding * 2
          spacing: Style.spacing.xs
          Row {
            width: parent.width
            Text {
              text: "Scroll speed"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              width: parent.width - valueText.width
              elide: Text.ElideRight
            }
            Text {
              id: valueText
              text: "×" + root.fmt(scrollSlider.liveValue, 2)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
          PanelSlider {
            id: scrollSlider
            width: parent.width
            bar: root.bar
            minimum: 0.1
            maximum: 5.0
            step: 0.05
            value: root.num("input:scroll_factor")
            onReleased: function(v) { service.set("input:scroll_factor", v.toFixed(2)) }
          }
        }

        // Sensitivity
        Column {
          width: parent.width - Style.spacing.panelPadding * 2
          spacing: Style.spacing.xs
          Row {
            width: parent.width
            Text {
              text: "Sensitivity"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              width: parent.width - sensValue.width
              elide: Text.ElideRight
            }
            Text {
              id: sensValue
              text: root.fmt(sensSlider.liveValue, 2)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
          PanelSlider {
            id: sensSlider
            width: parent.width
            bar: root.bar
            minimum: -1.0
            maximum: 1.0
            step: 0.05
            value: root.num("input:sensitivity")
            onReleased: function(v) { service.set("input:sensitivity", v.toFixed(2)) }
          }
        }

        // Accel profile
        Dropdown {
          width: parent.width - Style.spacing.panelPadding * 2
          label: "Acceleration profile"
          value: ["adaptive", "flat"][root.accelIndex()]
          options: [
            { value: "adaptive", label: "Adaptive (default)" },
            { value: "flat", label: "Flat (no acceleration)" }
          ]
          onChanged: function(v) { service.set("input:accel_profile", v) }
        }

        // Follow mouse
        Dropdown {
          width: parent.width - Style.spacing.panelPadding * 2
          label: "Focus follows mouse"
          value: ["0", "1", "2", "3"][root.followMouseIndex()]
          options: [
            { value: "0", label: "0 — Disabled" },
            { value: "1", label: "1 — Full (default)" },
            { value: "2", label: "2 — Loose" },
            { value: "3", label: "3 — On border crossing" }
          ]
          onChanged: function(v) { service.set("input:follow_mouse", v) }
        }

        Toggle {
          width: parent.width - Style.spacing.panelPadding * 2
          label: "Natural scroll"
          description: "Invert scroll direction (content follows fingers)"
          checked: root.boolOpt("input:natural_scroll")
          onClicked: service.set("input:natural_scroll", root.boolOpt("input:natural_scroll") ? 0 : 1)
        }

        Toggle {
          width: parent.width - Style.spacing.panelPadding * 2
          label: "Left-handed"
          description: "Swap left and right mouse buttons"
          checked: root.boolOpt("input:left_handed")
          onClicked: service.set("input:left_handed", root.boolOpt("input:left_handed") ? 0 : 1)
        }

        Toggle {
          width: parent.width - Style.spacing.panelPadding * 2
          label: "Middle-click paste"
          description: "Paste primary selection with the middle button"
          checked: root.boolOpt("input:middle_button_paste")
          onClicked: service.set("input:middle_button_paste", root.boolOpt("input:middle_button_paste") ? 0 : 1)
        }

        Toggle {
          width: parent.width - Style.spacing.panelPadding * 2
          label: "Emulate discrete scroll"
          description: "Turn high-res wheel events into discrete steps"
          checked: root.boolOpt("input:emulate_discrete_scroll")
          onClicked: service.set("input:emulate_discrete_scroll", root.boolOpt("input:emulate_discrete_scroll") ? 0 : 1)
        }

        // ------------------------------------------------ touchpad section
        PanelSeparator { width: parent.width - Style.spacing.panelPadding * 2 }
        PanelSectionHeader { text: "Touchpad" }

        Column {
          width: parent.width - Style.spacing.panelPadding * 2
          spacing: Style.spacing.xs
          Row {
            width: parent.width
            Text {
              text: "Touchpad scroll speed"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              width: parent.width - tpValue.width
              elide: Text.ElideRight
            }
            Text {
              id: tpValue
              text: "×" + root.fmt(tpSlider.liveValue, 2)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
          PanelSlider {
            id: tpSlider
            width: parent.width
            bar: root.bar
            minimum: 0.1
            maximum: 3.0
            step: 0.05
            value: root.num("input:touchpad:scroll_factor")
            onReleased: function(v) { service.set("input:touchpad:scroll_factor", v.toFixed(2)) }
          }
        }

        Toggle {
          width: parent.width - Style.spacing.panelPadding * 2
          label: "Natural scroll"
          checked: root.boolOpt("input:touchpad:natural_scroll")
          onClicked: service.set("input:touchpad:natural_scroll", root.boolOpt("input:touchpad:natural_scroll") ? 0 : 1)
        }

        Toggle {
          width: parent.width - Style.spacing.panelPadding * 2
          label: "Tap to click"
          checked: root.boolOpt("input:touchpad:tap-to-click")
          onClicked: service.set("input:touchpad:tap-to-click", root.boolOpt("input:touchpad:tap-to-click") ? 0 : 1)
        }

        Toggle {
          width: parent.width - Style.spacing.panelPadding * 2
          label: "Disable while typing"
          checked: root.boolOpt("input:touchpad:disable_while_typing")
          onClicked: service.set("input:touchpad:disable_while_typing", root.boolOpt("input:touchpad:disable_while_typing") ? 0 : 1)
        }

        Toggle {
          width: parent.width - Style.spacing.panelPadding * 2
          label: "Drag lock"
          description: "Lift finger mid-drag without dropping"
          checked: root.boolOpt("input:touchpad:drag_lock")
          onClicked: service.set("input:touchpad:drag_lock", root.boolOpt("input:touchpad:drag_lock") ? 0 : 1)
        }

        // ------------------------------------------------- devices section
        PanelSeparator { width: parent.width - Style.spacing.panelPadding * 2 }
        PanelSectionHeader { text: "Devices" }

        Repeater {
          model: service.devices
          delegate: Column {
            width: column.width - Style.spacing.panelPadding * 2
            spacing: Style.spacing.xs
            property var dev: modelData
            Row {
              width: parent.width
              Text {
                text: dev.name
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                width: parent.width - devValue.width
                elide: Text.ElideRight
              }
              Text {
                id: devValue
                text: "×" + root.fmt(devSlider.liveValue, 2)
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
            PanelSlider {
              id: devSlider
              width: parent.width
              bar: root.bar
              minimum: 0.1
              maximum: 5.0
              step: 0.05
              // -1 means "unset, inherits global" — show the global value then.
              value: dev.scrollFactor >= 0 ? dev.scrollFactor : root.num("input:scroll_factor")
              onReleased: function(v) { service.setDeviceScrollFactor(dev.name, v.toFixed(2)) }
            }
          }
        }

        Text {
          visible: service.devices.length === 0
          text: "No pointer devices found."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          visible: service.lastError !== ""
          text: service.lastError
          color: Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
          width: parent.width - Style.spacing.panelPadding * 2
        }
      }
    }
  }
}
