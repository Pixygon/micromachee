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
      mm.loadCovers()          // once per opening, not on the poll timer
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
      // Escape steps back one level at a time: out of a game to the shelf, off
      // a chosen cart back to the shelf, and only then out of the panel.
      onCloseRequested: {
        if (mm.playing) mm.stop()
        else if (mm.arming) mm.disarm()
        else root.close()
      }

      // T cycles the colour mode. It works on the shelf and mid-game, and a
      // running cart is restarted so the change is visible at once.
      onTextKey: function(ch) {
        if (ch === "t" || ch === "T") mm.nextTheme()
      }

      // The controller. Arrows or WASD, z and x — held, not typed, so a game
      // sees a button going down and coming up rather than a key repeat.
      Keys.onPressed: function(event) {
        // On the cover, X is the only button that does anything: it starts.
        if (mm.arming) {
          if (event.key === Qt.Key_X) { mm.startArmed(); event.accepted = true }
          return
        }
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

        // ── the console ─────────────────────────────────────────────────
        // Screen and buttons are one object, because on a handheld they are one
        // object. Every colour comes from the helper alongside the palette, so
        // the body and the screen can never drift apart.
        Rectangle {
          id: deck
          width: parent.width
          height: screenBox.height + pad.height + Style.space(12)
          visible: mm.playing || mm.arming
          color: mm.shellBody
          radius: Style.space(10)
          Behavior on color { ColorAnimation { duration: 180 } }

          Item {
            id: screenBox
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: width

            // Ask for the configured size, but never more than actually fits —
            // `fittedContentWidth` may have given us less than we wanted on a
            // small display, and an image wider than its bezel looks broken.
            //
            // Not called `scale`: Item already has one, for visual transforms.
            // QML shadows it rather than complaining, which is worse than an
            // error — it would work until something animated the real one.
            readonly property int pixelScale: Math.max(1, Math.min(root.pixelSize,
              Math.floor((width - root.screenInset * 2) / 128)))

            Rectangle {
              anchors.fill: parent
              anchors.margins: Style.space(4)
              color: mm.shellBezel
              radius: Style.space(5)
              border.width: 1
              border.color: Qt.rgba(mm.shellDim.r, mm.shellDim.g, mm.shellDim.b, 0.35)
              Behavior on color { ColorAnimation { duration: 180 } }
            }

            Image {
              id: screen
              anchors.centerIn: parent
              width: 128 * screenBox.pixelScale
              height: width
              // Playing shows the game; chosen-but-not-started shows the cover,
              // which is the same screen drawn by the same cart.
              source: mm.playing
                ? (mm.frame !== "" ? "data:image/png;base64," + mm.frame : "")
                : (mm.coverFor(mm.armedId) !== ""
                   ? "data:image/png;base64," + mm.coverFor(mm.armedId) : "")
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
              visible: mm.playing && mm.frame === "" && mm.lastError === ""
              text: "LOADING"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            // ── press X ───────────────────────────────────────────────────
            Rectangle {
              visible: mm.arming
              anchors.horizontalCenter: screen.horizontalCenter
              anchors.bottom: screen.bottom
              anchors.bottomMargin: Style.space(8)
              width: startLabel.implicitWidth + Style.space(16)
              height: startLabel.implicitHeight + Style.space(8)
              radius: height / 2
              color: Qt.rgba(0, 0, 0, 0.72)
              border.width: 1
              border.color: mm.shellAccent

              Text {
                id: startLabel
                anchors.centerIn: parent
                text: "PRESS X TO START"
                color: mm.shellText
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              // A slow blink, so it reads as waiting for you rather than as a
              // label that happens to be there.
              SequentialAnimation on opacity {
                running: mm.arming
                loops: Animation.Infinite
                NumberAnimation { to: 0.45; duration: 620 }
                NumberAnimation { to: 1.0; duration: 620 }
              }
            }
          }

          // ── the buttons ─────────────────────────────────────────────────
          // They light when the key is held and they can be pressed with the
          // mouse, because both routes end at the same `held` bitmask the cart
          // sees. Each carries the key that works it, since a cart printing
          // "PRESS O" cannot tell you that O is the z key.
          Item {
            id: pad
            anchors.top: screenBox.bottom
            anchors.topMargin: Style.space(4)
            anchors.left: parent.left
            anchors.right: parent.right
            height: Style.space(56)

            readonly property int cell: Style.space(16)
            readonly property int round: Style.space(22)

            Item {
              id: dpad
              anchors.left: parent.left
              anchors.leftMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              width: pad.cell * 3 + 4
              height: pad.cell * 3 + 4

              Repeater {
                model: [
                  { "bit": 2, "key": "W", "col": 1, "row": 0 },
                  { "bit": 0, "key": "A", "col": 0, "row": 1 },
                  { "bit": 3, "key": "S", "col": 1, "row": 2 },
                  { "bit": 1, "key": "D", "col": 2, "row": 1 }
                ]
                delegate: Rectangle {
                  required property var modelData
                  readonly property bool down: (mm.held & (1 << modelData.bit)) !== 0
                  x: modelData.col * (pad.cell + 2)
                  y: modelData.row * (pad.cell + 2)
                  width: pad.cell
                  height: pad.cell
                  radius: Style.space(3)
                  color: down ? mm.shellAccent : mm.shellDim
                  opacity: mm.playing ? 1.0 : 0.45

                  Text {
                    anchors.centerIn: parent
                    text: modelData.key
                    color: mm.shellBezel
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                  }

                  MouseArea {
                    anchors.fill: parent
                    enabled: mm.playing
                    onPressed: mm.setButton(modelData.bit, true)
                    onReleased: mm.setButton(modelData.bit, false)
                    onCanceled: mm.setButton(modelData.bit, false)
                  }
                }
              }
            }

            Text {
              anchors.centerIn: parent
              text: "MICROMACHEE"
              color: mm.shellDim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.letterSpacing: 2
              opacity: 0.7
            }

            Row {
              anchors.right: parent.right
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)

              Repeater {
                // Big letter is what a cart calls the button; small letter is
                // the key you actually press.
                model: [
                  { "bit": 4, "name": "O", "key": "Z" },
                  { "bit": 5, "name": "X", "key": "X" }
                ]
                delegate: Column {
                  required property var modelData
                  spacing: 1

                  Rectangle {
                    readonly property bool down: (mm.held & (1 << modelData.bit)) !== 0
                    width: pad.round
                    height: pad.round
                    radius: width / 2
                    color: down ? mm.shellAccent : mm.shellDim
                    opacity: (mm.playing || (mm.arming && modelData.bit === 5)) ? 1.0 : 0.45

                    Text {
                      anchors.centerIn: parent
                      text: modelData.name
                      color: mm.shellBezel
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                    }

                    MouseArea {
                      anchors.fill: parent
                      enabled: mm.playing || (mm.arming && modelData.bit === 5)
                      onPressed: {
                        if (mm.arming) mm.startArmed()
                        else mm.setButton(modelData.bit, true)
                      }
                      onReleased: if (mm.playing) mm.setButton(modelData.bit, false)
                      onCanceled: if (mm.playing) mm.setButton(modelData.bit, false)
                    }
                  }

                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.key
                    color: mm.shellDim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                }
              }
            }
          }
        }

        RowLayout {
          width: parent.width
          visible: mm.playing || mm.arming
          Text {
            text: mm.playing ? mm.playingTitle : mm.armedTitle
            color: mm.shellText
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            Layout.fillWidth: true
            elide: Text.ElideRight
          }
          Text {
            visible: mm.playing
            text: mm.score + (mm.best > 0 ? "  /  BEST " + mm.best : "")
            color: mm.shellDim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        Text {
          visible: mm.playing || mm.arming
          width: parent.width
          text: mm.arming ? "X STARTS · ESC GOES BACK"
                          : "ARROWS OR WASD · Z AND X · T THEME · ESC BACK"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          horizontalAlignment: Text.AlignHCenter
        }

        // ── the shelf ───────────────────────────────────────────────────
        PanelHero {
          visible: !mm.playing && !mm.arming
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
          visible: !mm.playing && !mm.arming && mm.themes.length > 1
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
          model: (mm.playing || mm.arming) ? [] : mm.carts
          delegate: Item {
            required property var modelData
            width: body.width
            height: Style.space(46)

            Rectangle {
              anchors.fill: parent
              anchors.rightMargin: Style.space(2)
              radius: Style.cornerRadius
              color: hover.containsMouse
                ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.13)
                : "transparent"
            }

            Rectangle {
              id: thumb
              anchors.left: parent.left
              anchors.leftMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(38)
              height: width
              radius: Style.space(3)
              color: mm.shellBezel
              clip: true

              Image {
                anchors.fill: parent
                anchors.margins: 1
                source: mm.coverFor(modelData.id) !== ""
                  ? "data:image/png;base64," + mm.coverFor(modelData.id) : ""
                smooth: false
                mipmap: false
                fillMode: Image.PreserveAspectFit
                cache: false
              }

              Text {
                anchors.centerIn: parent
                visible: mm.coverFor(modelData.id) === ""
                text: String(modelData.title || "?").substring(0, 1).toUpperCase()
                color: mm.shellDim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }
            }

            Column {
              anchors.left: thumb.right
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - thumb.width - Style.space(70)
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
                // Choosing a cart raises its cover; X starts it. The pause is
                // the point — you get a moment to look at it and get your
                // hands on the keys before anything is moving.
                mm.arm(modelData.id, modelData.title)
                Qt.callLater(function() { keys.forceActiveFocus() })
              }
            }
          }
        }

        Text {
          visible: !mm.playing && !mm.arming && mm.installed && mm.carts.length === 0
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
