import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// AULA SC580 bar widget + popup panel.
//
// Everything that touches the mouse goes through `sc580ctl` (bin/sc580ctl in
// this repo): the panel runs `sc580ctl status --json` to learn the link type,
// battery, active DPI stage and the stored config, and runs one `sc580ctl ...`
// command per change. The CLI persists the config, so the panel keeps no state
// of its own beyond what the last status call reported.
Panel {
  id: root
  moduleName: "io.github.crucialjun.aula-sc580"
  ipcTarget: "io.github.crucialjun.aula-sc580"

  // The driver ships inside the plugin folder, so `omarchy plugin add` is enough.
  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string cliPath: pluginDir + "/bin/sc580ctl"
  readonly property var cli: ["python3", cliPath]
  readonly property bool permissionDenied: !!(status && status.permission_denied)

  property var status: null
  property string error: ""
  property bool busy: false
  property string pendingArmed: ""     // "reset" once the reset button was pressed once
  property int cursorIndex: -1

  readonly property var cfg: (status && status.config) ? status.config : null
  readonly property bool connected: !!(status && status.connected)
  readonly property var info: (status && status.info) ? status.info : ({})
  readonly property bool online: connected && info.online !== false
  readonly property bool wireless: connected && status.link === "wireless"
  readonly property real batteryFraction: {
    var p = Number(info.battery)
    return isFinite(p) ? Math.max(0, Math.min(1, p / 100)) : 0
  }
  readonly property var stages: cfg ? cfg.dpi.stages : []
  readonly property int deviceStage: (status && status.dpi_stage) ? Number(status.dpi_stage) : 0
  readonly property int activeStage: deviceStage > 0 ? deviceStage : (cfg ? Number(cfg.dpi.current) + 1 : 0)
  readonly property int activeDpi: (activeStage >= 1 && activeStage <= stages.length) ? Number(stages[activeStage - 1]) : 0
  readonly property bool showBattery: wireless && isFinite(Number(info.battery))

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function updateStatus(raw) {
    var next = Model.parseStatus(raw)
    if (!next) {
      if (String(raw || "").trim() !== "") error = Commons.I18n.t("sc580.badStatus", "sc580ctl returned something unexpected")
      return
    }
    status = next
    error = next.error && !next.connected ? "" : (next.error || "")
  }

  // One command at a time; the CLI opens the hidraw node exclusively per call.
  function run(args) {
    if (actionProc.running) {
      error = Commons.I18n.t("sc580.busy", "Still talking to the mouse — try again in a second")
      return
    }
    error = ""
    busy = true
    actionProc.command = root.cli.concat(args)
    actionProc.running = true
  }

  function selectStage(n) { run(["dpi", "stage", String(n)]) }
  function setStageDpi(n, dpi) { run(["dpi", "set", String(n), String(Model.clampDpi(dpi))]) }
  function addStage() {
    if (stages.length >= Model.MAX_STAGES) return
    run(["dpi", "set", String(stages.length + 1), String(Model.clampDpi(stages[stages.length - 1] * 1.5))])
  }
  function removeStage() {
    if (stages.length <= 1) return
    run(["dpi", "remove", String(stages.length)])
  }
  function setRate(hz) { run(["rate", String(hz)]) }
  function setKey(button, fn) { run(["key", String(button), String(fn)]) }
  function releaseCapture() {
    if (panel.loadedContent) panel.loadedContent.forceActiveFocus()
  }
  function setShortcut(button, text) {
    var spec = Model.normalizeShortcut(text)
    if (!spec) { error = Commons.I18n.t("sc580.badShortcut", "Type a key with optional ctrl/shift/alt/super, e.g. ctrl+shift+t"); return }
    setKey(button, spec)
  }
  function setSleep(seconds) { run(["sleep", String(seconds)]) }
  function setDebounce(ms) { run(["debounce", String(ms)]) }
  function setFlag(name, on) { run(["set", name, on ? "on" : "off"]) }
  function applyAll() { run(["apply"]) }
  function grantAccess() {
    if (grantProc.running) return
    error = ""
    busy = true
    grantProc.running = true
  }
  function factoryReset() {
    if (pendingArmed !== "reset") { pendingArmed = "reset"; disarm.restart(); return }
    pendingArmed = ""
    run(["reset"])
  }

  Timer { id: disarm; interval: 4000; onTriggered: root.pendingArmed = "" }

  onOpenedChanged: if (opened) { error = ""; pendingArmed = ""; refresh() }

  // Keep the bar icon honest even while the panel is closed (battery, link).
  Timer { interval: 60000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
  Timer { interval: 5000; running: root.opened; repeat: true; onTriggered: root.refresh() }

  Process {
    id: statusProc
    command: root.cli.concat(["status", "--json", "--compact"])
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateStatus(text) }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(code) {
      if (code !== 0 && !root.status) root.error = Commons.I18n.t("sc580.noCli", "Could not run bin/sc580ctl — is python3 installed?")
    }
  }

  // Installs udev/70-aula-sc580.rules so the hidraw node is user-accessible.
  Process {
    id: grantProc
    command: ["pkexec", "sh", "-c",
      "install -m 0644 \"$1\" /etc/udev/rules.d/70-aula-sc580.rules && udevadm control --reload-rules && udevadm trigger --subsystem-match=hidraw",
      "sh", root.pluginDir + "/udev/70-aula-sc580.rules"]
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: { var t = String(text || "").trim(); if (t !== "") root.error = t } }
    onExited: function(code) {
      root.busy = false
      if (code === 0) root.error = Commons.I18n.t("sc580.granted", "Access granted — replug the mouse or receiver if it still shows as not connected")
      root.refresh()
    }
  }

  Process {
    id: actionProc
    stderr: StdioCollector {
      id: actionErr
      waitForEnd: true
      onStreamFinished: {
        var t = String(text || "").trim()
        if (t !== "") root.error = t.replace(/^sc580ctl: /, "")
      }
    }
    onExited: function(code) {
      root.busy = false
      root.refresh()
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Model.batteryIcon(root.status)
    opacity: root.connected ? 1.0 : 0.45
    labelText: (root.showBattery && !vertical) ? Commons.I18n.formatNumber(Math.round(root.batteryFraction * 100)) + "%" : ""
    slotSize: Style.bar.iconSlot * ((root.showBattery && !vertical) ? 2 : 1)
    tooltipText: ""
    onPressed: function(b) {
      if (b === Qt.RightButton) { root.refresh(); return }
      root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      anchors.fill: parent
      implicitHeight: column.implicitHeight
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // ---------- Hero ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroDpi.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: Model.batteryIcon(root.status)
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroDpi.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "AULA SC580"
              textFormat: Text.PlainText
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }
            Text {
              text: Model.statusLine(root.status)
              textFormat: Text.PlainText
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Column {
            id: heroDpi
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            Text {
              textFormat: Text.PlainText
              text: root.activeDpi > 0 ? Commons.I18n.formatNumber(root.activeDpi) : "—"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.displayLarge
              font.bold: true
              anchors.right: parent.right
            }
            Text {
              textFormat: Text.PlainText
              text: "DPI"
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              anchors.right: parent.right
            }
          }
        }

        // ---------- Battery bar (wireless only) ----------
        Item {
          visible: root.showBattery
          width: parent.width
          implicitHeight: Style.space(8)
          Rectangle {
            id: barTrack
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
          }
          Rectangle {
            anchors.left: barTrack.left
            anchors.verticalCenter: barTrack.verticalCenter
            height: barTrack.height
            radius: barTrack.radius
            color: root.bar.foreground
            width: Math.max(barTrack.height, barTrack.width * root.batteryFraction)
            Behavior on width { NumberAnimation { duration: Style.duration(320); easing.type: Easing.OutCubic } }
          }
        }

        // ---------- Not connected / error ----------
        Text {
          visible: !root.connected
          width: parent.width
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: (root.status && root.status.error) ? root.status.error
                : Commons.I18n.t("sc580.notConnected", "Plug in the mouse or its 2.4G receiver. Settings below are saved and pushed when it reappears.")
          color: Qt.darker(root.bar.foreground, 1.3)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Button {
          visible: root.permissionDenied
          width: parent.width
          iconText: "󰌾"
          text: Commons.I18n.t("sc580.grantAccess", "Grant device access (installs a udev rule)")
          fontSize: Style.font.bodySmall
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          bordered: true
          enabled: !root.busy
          onClicked: root.grantAccess()
        }

        PanelSeparator { foreground: root.bar.foreground }

        // ---------- DPI stages ----------
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: !!root.cfg

          Item {
            width: parent.width
            implicitHeight: dpiHeader.implicitHeight
            PanelSectionHeader {
              id: dpiHeader
              text: Commons.I18n.t("sc580.dpiStages", "DPI stages")
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }
            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(4)
              PanelActionButton {
                iconText: "󰍴"
                tooltipText: Commons.I18n.t("sc580.removeStage", "Remove last stage")
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                enabled: root.stages.length > 1 && !root.busy
                opacity: enabled ? 1 : 0.35
                onClicked: root.removeStage()
              }
              PanelActionButton {
                iconText: "󰐕"
                tooltipText: Commons.I18n.t("sc580.addStage", "Add a stage")
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                enabled: root.stages.length < Model.MAX_STAGES && !root.busy
                opacity: enabled ? 1 : 0.35
                onClicked: root.addStage()
              }
            }
          }

          Row {
            id: stageRow
            width: parent.width
            spacing: Style.space(6)
            readonly property real cellWidth: root.stages.length > 0
              ? (width - spacing * (root.stages.length - 1)) / root.stages.length : 0

            Repeater {
              model: root.stages
              Button {
                required property var modelData
                required property int index
                width: stageRow.cellWidth
                text: Commons.I18n.formatNumber(Number(modelData))
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.space(4)
                verticalPadding: Style.spacing.controlPaddingY
                bordered: true
                active: root.activeStage === index + 1
                onClicked: root.selectStage(index + 1)
              }
            }
          }

          // Slider edits the active stage's DPI; the value is pushed on release.
          Item {
            width: parent.width
            implicitHeight: dpiSlider.implicitHeight
            visible: root.activeStage > 0
            PanelSlider {
              id: dpiSlider
              bar: root.bar
              anchors.left: parent.left
              anchors.right: sliderValue.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              minimum: Model.DPI_MIN
              maximum: Model.DPI_MAX
              step: Model.DPI_STEP
              integer: true
              value: root.activeDpi
              onReleased: function(v) { root.setStageDpi(root.activeStage, v) }
            }
            Text {
              id: sliderValue
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: Commons.I18n.formatNumber(Math.round(dpiSlider.liveValue))
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              width: Style.space(48)
              horizontalAlignment: Text.AlignRight
            }
          }
        }

        // ---------- Polling rate ----------
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: !!root.cfg
          PanelSectionHeader {
            text: Commons.I18n.t("sc580.pollingRate", "Polling rate")
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }
          Row {
            id: rateRow
            width: parent.width
            spacing: Style.space(6)
            readonly property real cellWidth: (width - spacing * (Model.RATES.length - 1)) / Model.RATES.length
            Repeater {
              model: Model.RATES
              Button {
                required property var modelData
                width: rateRow.cellWidth
                text: Commons.I18n.formatNumber(Number(modelData)) + " Hz"
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.space(4)
                verticalPadding: Style.spacing.controlPaddingY
                bordered: true
                active: !!root.cfg && Number(root.cfg.rate) === Number(modelData)
                onClicked: root.setRate(modelData)
              }
            }
          }
        }

        // ---------- Power ----------
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: !!root.cfg
          PanelSectionHeader {
            text: Commons.I18n.t("sc580.power", "Power")
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }
          SettingRow {
            label: Commons.I18n.t("sc580.sleepAfter", "Sleep after")
            Dropdown {
              width: Style.spacing.dropdownWidth
              showLabel: false
              fontFamily: root.bar.fontFamily
              options: Model.sleepOptions()
              value: root.cfg ? String(root.cfg.sleep_seconds) : ""
              onChanged: function(v) { if (root.cfg && v !== String(root.cfg.sleep_seconds)) root.setSleep(v) }
            }
          }
          SettingRow {
            label: Commons.I18n.t("sc580.wakeOnMove", "Wake up when moved")
            ToggleSwitch {
              checked: !!(root.cfg && root.cfg.wake_on_move)
              busy: root.busy
              foreground: root.bar.foreground
              onToggled: root.setFlag("wake-on-move", !(root.cfg && root.cfg.wake_on_move))
            }
          }
        }

        // ---------- Buttons ----------
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: !!root.cfg
          PanelSectionHeader {
            text: Commons.I18n.t("sc580.buttons", "Buttons")
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }
          Repeater {
            model: Model.BUTTONS
            // One button: function dropdown, plus an inline shortcut editor
            // when "Keyboard shortcut…" is chosen (or already in use).
            Column {
              id: keyRow
              required property var modelData
              readonly property string current: root.cfg ? String(root.cfg.keys[String(modelData.id)] || "") : ""
              readonly property bool isCustom: Model.isShortcut(current)
              property bool editing: false
              readonly property bool showEditor: editing || isCustom
              width: parent.width
              spacing: Style.space(6)
              onCurrentChanged: if (isCustom) editing = false

              SettingRow {
                label: keyRow.modelData.label
                Dropdown {
                  width: Style.spacing.dropdownWidth
                  showLabel: false
                  fontFamily: root.bar.fontFamily
                  options: Model.keyOptions(keyRow.current)
                  value: keyRow.editing && !keyRow.isCustom ? Model.CUSTOM : keyRow.current
                  onChanged: function(v) {
                    if (v === Model.CUSTOM) { keyRow.editing = true; return }
                    keyRow.editing = false
                    if (v !== keyRow.current) root.setKey(keyRow.modelData.id, v)
                  }
                }
              }

              // Click the field, press the combination; it is assigned on key-up.
              Item {
                visible: keyRow.showEditor
                width: parent.width
                implicitHeight: captureBox.implicitHeight

                Rectangle {
                  id: captureBox
                  anchors.left: parent.left
                  anchors.right: cancelCapture.left
                  anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  implicitHeight: Style.spacing.controlHeight
                  radius: Style.cornerRadius
                  color: activeFocus ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.16)
                                     : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.07)
                  border.width: 1
                  border.color: activeFocus ? root.bar.foreground : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.3)

                  property string heldMods: ""
                  focus: false
                  activeFocusOnTab: true

                  Keys.priority: Keys.BeforeItem
                  Keys.onPressed: function(event) {
                    event.accepted = true
                    if (event.key === Qt.Key_Escape && !(event.modifiers & ~Qt.KeypadModifier)) {
                      captureBox.heldMods = ""; keyRow.editing = false; root.releaseCapture(); return
                    }
                    if (Model.isModifierKey(event.key)) {
                      captureBox.heldMods = Model.modsFromQt(event.modifiers | Model.modifierFlagForKey(event.key)).join(" + ")
                      return
                    }
                    var spec = Model.shortcutFromEvent(event.key, event.modifiers)
                    if (!spec) return
                    captureBox.heldMods = ""
                    root.setKey(keyRow.modelData.id, spec)
                    keyRow.editing = false
                    root.releaseCapture()
                  }
                  Keys.onReleased: function(event) {
                    event.accepted = true
                    if (Model.isModifierKey(event.key)) captureBox.heldMods = Model.modsFromQt(event.modifiers).join(" + ")
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: captureBox.forceActiveFocus()
                  }

                  Text {
                    anchors.fill: parent
                    anchors.leftMargin: Style.spacing.controlPaddingX
                    anchors.rightMargin: Style.spacing.controlPaddingX
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    color: root.bar.foreground
                    opacity: captureBox.activeFocus || keyRow.isCustom ? 1 : 0.6
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    text: captureBox.activeFocus
                      ? (captureBox.heldMods !== "" ? captureBox.heldMods + " + …"
                                                     : Commons.I18n.t("sc580.pressKeys", "Press the key combination…"))
                      : (keyRow.isCustom ? Model.prettyShortcut(keyRow.current)
                                         : Commons.I18n.t("sc580.clickToCapture", "Click here, then press keys"))
                  }
                }

                PanelActionButton {
                  id: cancelCapture
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: captureBox.activeFocus ? "󰅖" : "󰌌"
                  tooltipText: captureBox.activeFocus
                    ? Commons.I18n.t("sc580.cancelCapture", "Stop capturing (Esc)")
                    : Commons.I18n.t("sc580.startCapture", "Capture a key combination")
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  onClicked: {
                    if (captureBox.activeFocus) { captureBox.heldMods = ""; keyRow.editing = false; root.releaseCapture() }
                    else captureBox.forceActiveFocus()
                  }
                }
              }

              Text {
                visible: keyRow.showEditor
                width: parent.width
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: Commons.I18n.t("sc580.captureNote", "Combos Hyprland has bound (most Super+…) never reach the panel — set those with: sc580ctl key N kbd:super+e")
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        // ---------- Advanced ----------
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: !!root.cfg
          PanelSectionHeader {
            text: Commons.I18n.t("sc580.advanced", "Advanced")
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }
          SettingRow {
            label: Commons.I18n.t("sc580.debounce", "Click debounce")
            Dropdown {
              width: Style.spacing.dropdownWidth
              showLabel: false
              fontFamily: root.bar.fontFamily
              options: Model.debounceOptions()
              value: root.cfg ? String(root.cfg.debounce_ms) : ""
              onChanged: function(v) { if (root.cfg && v !== String(root.cfg.debounce_ms)) root.setDebounce(v) }
            }
          }
          SettingRow {
            label: Commons.I18n.t("sc580.angleSnap", "Angle snapping")
            ToggleSwitch {
              checked: !!(root.cfg && root.cfg.angle_snap)
              busy: root.busy
              foreground: root.bar.foreground
              onToggled: root.setFlag("angle-snap", !(root.cfg && root.cfg.angle_snap))
            }
          }
          SettingRow {
            label: Commons.I18n.t("sc580.ripple", "Ripple control")
            ToggleSwitch {
              checked: !!(root.cfg && root.cfg.ripple)
              busy: root.busy
              foreground: root.bar.foreground
              onToggled: root.setFlag("ripple", !(root.cfg && root.cfg.ripple))
            }
          }
        }

        PanelSeparator { foreground: root.bar.foreground; visible: !!root.cfg }

        // ---------- Footer ----------
        Row {
          width: parent.width
          spacing: Style.space(6)
          visible: !!root.cfg
          readonly property real cellWidth: (width - spacing) / 2
          Button {
            width: parent.cellWidth
            iconText: "󰑓"
            text: Commons.I18n.t("sc580.applyAll", "Push all settings")
            fontSize: Style.font.bodySmall
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            bordered: true
            enabled: root.connected && !root.busy
            opacity: enabled ? 1 : 0.5
            onClicked: root.applyAll()
          }
          Button {
            width: parent.cellWidth
            iconText: "󰁯"
            text: root.pendingArmed === "reset"
              ? Commons.I18n.t("sc580.confirmReset", "Really reset?")
              : Commons.I18n.t("sc580.factoryReset", "Factory reset")
            fontSize: Style.font.bodySmall
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            bordered: true
            active: root.pendingArmed === "reset"
            enabled: root.connected && !root.busy
            opacity: enabled ? 1 : 0.5
            onClicked: root.factoryReset()
          }
        }

        Text {
          visible: root.error !== ""
          width: parent.width
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: root.error
          color: root.bar.foreground
          opacity: 0.8
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  // Label on the left, a control on the right.
  component SettingRow: Item {
    id: settingRow
    property string label: ""
    default property alias control: controlSlot.children
    width: parent ? parent.width : 0
    implicitHeight: Math.max(settingLabel.implicitHeight, controlSlot.childrenRect.height)

    Text {
      id: settingLabel
      textFormat: Text.PlainText
      text: settingRow.label
      color: root.bar.foreground
      opacity: 0.75
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
      anchors.left: parent.left
      anchors.right: controlSlot.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
    }
    Item {
      id: controlSlot
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: childrenRect.width
      height: childrenRect.height
    }
  }
}
