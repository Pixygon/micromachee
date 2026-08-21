// Micromachee — a console in the bar.
//
// The bar shows one thing: a screen glyph and how many carts are on the shelf.
// Everything else is behind the click, because a game is not glanceable and
// pretending otherwise would make the widget shout.
//
// The panel has exactly two states — the shelf, and a game. There is no menu
// system, no settings page, no cartridge browser with filters. A console this
// small earns its charm by having almost no chrome.

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

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // How many screen pixels one console pixel gets. A WHOLE number, always: at
  // 2.05x some console pixels are two screen pixels wide and some are three,
  // and the whole screen shimmers as anything moves across it. That is the one
  // thing an eight-colour console cannot afford, and it gets worse the bigger
  // the screen is — so growing it and squaring it up are the same job.
  readonly property int pixelSize: {
    var n = parseInt(String(settings && settings.screenScale !== undefined
                            ? settings.screenScale : 3), 10)
    if (!isFinite(n)) n = 3
    return Math.max(2, Math.min(6, n))
  }
  readonly property int screenInset: Style.space(7)
  readonly property int consoleWidth: 128 * pixelSize + screenInset * 2

  readonly property string glyph: "▦"
  readonly property string barLabel: mm.carts.length > 0 ? glyph + " " + mm.carts.length : glyph

  readonly property string tooltip: {
    if (!mm.installed) return "Micromachee — helper not installed"
    if (mm.carts.length === 0) return "Micromachee — no carts yet"
    return "Micromachee — " + mm.carts.length + " cart" + (mm.carts.length === 1 ? "" : "s")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // Closing the panel stops the game. A console nobody is looking at should
  // not be drawing thirty frames a second.
  onOpenedChanged: {
    if (opened) {
      mm.refresh()
      Qt.callLater(function() { keys.forceActiveFocus() })
    } else {
      mm.stop()
    }
  }

  Service {
    id: mm
    settings: root.settings
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function play(id: string): string { root.open(); mm.play(id, id); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barLabel
    active: mm.playing
    tooltipText: root.tooltip
    onPressed: function(buttonCode) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(Math.max(Style.space(276), root.consoleWidth))
    contentHeight: panel.fittedContentHeight(body.implicitHeight, Style.space(900))

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onCloseRequested: mm.playing ? mm.stop() : root.close()

      // T cycles the colour mode. It works on the shelf and mid-game, and a
      // running cart is restarted so the change is visible at once.
      onTextKey: function(ch) {
        if (ch === "t" || ch === "T") mm.nextTheme()
      }

      // The controller. Arrows or WASD, z and x — held, not typed, so a game
      // sees a button going down and coming up rather than a key repeat.
      Keys.onPressed: function(event) {
        if (!mm.playing) return
        var b = buttonFor(event.key)
        if (b >= 0) { mm.setButton(b, true); event.accepted = true }
      }
      Keys.onReleased: function(event) {
        if (!mm.playing) return
        var b = buttonFor(event.key)
        if (b >= 0) { mm.setButton(b, false); event.accepted = true }
      }

      function buttonFor(key) {
        switch (key) {
          case Qt.Key_Left:  case Qt.Key_A: return 0
          case Qt.Key_Right: case Qt.Key_D: return 1
          case Qt.Key_Up:    case Qt.Key_W: return 2
          case Qt.Key_Down:  case Qt.Key_S: return 3
          case Qt.Key_Z:     case Qt.Key_Space: return 4
          case Qt.Key_X:     return 5
        }
        return -1
      }

      Column {
        id: body
        width: parent.width
        spacing: Style.space(10)

        // ── the screen ──────────────────────────────────────────────────
        Item {
          id: screenBox
          width: parent.width
          height: width          // square, always
          visible: mm.playing

          // Ask for the configured size, but never more than actually fits —
          // `fittedContentWidth` may have given us less than we wanted on a
          // small display, and an image wider than its bezel looks broken.
          //
          // Not called `scale`: Item already has one, for visual transforms.
          // QML shadows it rather than complaining, which is worse than an
          // error — it would work until something animated the real one.
          readonly property int pixelScale: Math.max(1, Math.min(root.pixelSize,
            Math.floor((width - root.screenInset * 2) / 128)))

          // The console body. Its colours come from the helper with the
          // palette, so the shell and the screen can never drift apart.
          Rectangle {
            anchors.fill: parent
            color: mm.shellBody
            radius: Style.space(8)
            Behavior on color { ColorAnimation { duration: 180 } }

            Rectangle {
              anchors.fill: parent
              anchors.margins: Style.space(5)
              color: mm.shellBezel
              radius: Style.space(4)
              border.width: 1
              border.color: Qt.rgba(mm.shellDim.r, mm.shellDim.g, mm.shellDim.b, 0.35)
              Behavior on color { ColorAnimation { duration: 180 } }
            }
          }

          Image {
            id: screen
            anchors.centerIn: parent
            width: 128 * screenBox.pixelScale
            height: width
            source: mm.frame !== "" ? "data:image/png;base64," + mm.frame : ""
            // 128 pixels blown up: never interpolate, or the whole point of an
            // eight-colour console is lost to a blur.
            smooth: false
            mipmap: false
            fillMode: Image.Stretch
            cache: false
            asynchronous: false
          }

          Text {
            anchors.centerIn: parent
            visible: mm.frame === "" && mm.lastError === ""
            text: "LOADING"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        RowLayout {
          width: parent.width
          visible: mm.playing
          Text {
            text: mm.playingTitle
            color: mm.shellText
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            Layout.fillWidth: true
            elide: Text.ElideRight
          }
          Text {
            text: mm.score + (mm.best > 0 ? "  /  BEST " + mm.best : "")
            color: mm.shellDim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        Text {
          visible: mm.playing
          width: parent.width
          text: "ARROWS OR WASD · Z AND X · T THEME · ESC BACK"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          horizontalAlignment: Text.AlignHCenter
        }

        // ── the shelf ───────────────────────────────────────────────────
        PanelHero {
          visible: !mm.playing
          width: parent.width
          title: "Micromachee"
          meta: mm.installed
            ? (mm.carts.length === 0
               ? "no carts — micromachee sync"
               : mm.carts.length + (mm.carts.length === 1 ? " cart" : " carts"))
            : "helper not installed"
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            Text {
              text: root.glyph
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
        }

        Item {
          visible: !mm.playing && mm.themes.length > 1
          width: parent.width
          height: Style.space(22)

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            text: "COLOUR MODE"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Row {
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            // The palette itself is the label: eight swatches say more about a
            // colour mode than its name does.
            Row {
              anchors.verticalCenter: parent.verticalCenter
              spacing: 1
              Repeater {
                model: [mm.shellBezel, mm.shellDim, mm.shellAccent, mm.shellText]
                delegate: Rectangle {
                  required property var modelData
                  width: Style.space(6); height: Style.space(6)
                  radius: 1
                  color: modelData
                  Behavior on color { ColorAnimation { duration: 180 } }
                }
              }
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: mm.themeId
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: mm.nextTheme()
          }
        }

        Text {
          visible: mm.lastError !== ""
          width: parent.width
          text: mm.lastError
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Repeater {
          model: mm.playing ? [] : mm.carts
          delegate: Item {
            required property var modelData
            width: body.width
            height: Style.space(34)

            Rectangle {
              anchors.fill: parent
              anchors.rightMargin: Style.space(2)
              radius: Style.cornerRadius
              color: hover.containsMouse
                ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.13)
                : "transparent"
            }

            Column {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - Style.space(60)
              spacing: 1

              Text {
                width: parent.width
                text: modelData.title
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }
              Text {
                width: parent.width
                text: modelData.about !== "" ? modelData.about : ("by " + modelData.author)
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
            }

            Text {
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              visible: Number(modelData.best || 0) > 0
              text: modelData.best
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            MouseArea {
              id: hover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                mm.play(modelData.id, modelData.title)
                Qt.callLater(function() { keys.forceActiveFocus() })
              }
            }
          }
        }

        Text {
          visible: !mm.playing && mm.installed && mm.carts.length === 0
          width: parent.width
          text: "No carts on the shelf. `micromachee sync` fetches them, or drop a .lua file in the carts folder — that is all installing a game is."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
