// micromachee — a bar widget for Omarchy Quattro.
//
// The bar is a hostile place to write UI: you get a glyph and a few characters,
// read at a glance, next to a dozen other things competing for the same eye. So
// the rule this file follows is that the bar shows ONE fact — the one you would
// want to know without clicking — and everything else lives in the panel behind
// it.
//
// No logic here. This asks Service.qml what is true and draws it.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.pixygon.micromachee"
  ipcTarget: "io.pixygon.micromachee"
  manageIpc: false

  // Inherit the bar's own colours and font rather than picking your own: a
  // widget that ignores the theme is the one the user removes first.
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string glyph: "◆"
  readonly property color glyphColor: service.ready ? foreground : dim
  readonly property string barLabel: service.ready ? glyph + " " + service.headline : glyph

  readonly property string tooltip: {
    if (!service.installed) return "micromachee — helper not installed"
    if (service.lastError !== "") return service.lastError
    return "micromachee — " + service.headline
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    service.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: service
    settings: root.settings
  }

  // Lets other things drive the widget: `qs ipc call io.pixygon.micromachee toggle`.
  // Worth keeping — it is how a keybind reaches you.
  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { service.refresh(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barLabel
    active: service.ready
    tooltipText: root.tooltip
    onPressed: function(buttonCode) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(460))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTextKey: function(t) {
        if (t === "r" || t === "R") service.refresh()
      }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        Column {
          id: column
          width: parent.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "micromachee"
            meta: service.installed ? service.headline : "helper not installed"
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: root.glyph
                color: root.glyphColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          Text {
            visible: service.lastError !== "" || service.actionStatus !== ""
            width: parent.width
            text: service.lastError !== "" ? service.lastError : service.actionStatus
            color: service.lastError !== "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          // ── Your UI goes here. ────────────────────────────────────────────
          // Components worth knowing, all from qs.Ui: PanelSectionHeader,
          // PanelSeparator, PanelActionButton (+ PanelToolTip inside it), and
          // ToggleSwitch. Use Style.space() for every gap so the widget scales
          // with the user's bar instead of fighting it.

          PanelSeparator { foreground: root.foreground }

          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            PanelActionButton {
              id: refreshBtn
              iconText: "󰑐"
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: service.installed && !service.busy
              Layout.alignment: Qt.AlignVCenter
              onClicked: service.refresh()
              PanelToolTip { visible: refreshBtn.containsMouse; text: "Refresh"; fontFamily: root.fontFamily }
            }
          }

          Text {
            visible: !service.installed
            width: parent.width
            text: "Install the helper: ./install.sh — see the README"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
