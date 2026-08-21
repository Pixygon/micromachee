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
  readonly property int pixelSize: Math.max(2, Math.min(6, mm.scale || 3))

  readonly property int screenInset: Style.space(7)
  readonly property int consoleWidth: 128 * pixelSize + screenInset * 2

  // True while a text field has the keyboard. The panel's letter shortcuts have
  // to stand down, or typing a game called "Retro" cycles the theme twice.
  readonly property bool typing: nameField.activeFocus || promptField.activeFocus
                                 || reviseField.activeFocus

  /// Which cart the shelf has highlighted, and how wide the grid is.
  property int shelfIndex: 0
  readonly property int shelfColumns: 3

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
      mm.resume()              // a closed panel paused it; pick it back up
      Qt.callLater(function() { keys.forceActiveFocus() })
    } else {
      // Not `stop()`. Closing the bar to look at something else should cost you
      // a moment, not the run you were in the middle of.
      mm.pause()
    }
  }

  Service {
    id: mm
    settings: root.settings
  }

  // Carts come and go — syncing, publishing, discarding — and a selection that
  // points past the end of the shelf highlights nothing.
  Connections {
    target: mm
    function onCartsChanged() {
      root.shelfIndex = Math.max(0, Math.min(root.shelfIndex, mm.carts.length - 1))
    }
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
        if (mm.creating) mm.closeCreate()
        else if (mm.playing) mm.stop()
        else if (mm.arming) mm.disarm()
        else root.close()
      }

      // T cycles the colour mode. It works on the shelf and mid-game, and a
      // running cart is restarted so the change is visible at once.
      onTextKey: function(ch) {
        if (root.typing) return
        if (ch === "t" || ch === "T") mm.nextTheme()
      }

      // The controller. Arrows or WASD, z and x — held, not typed, so a game
      // sees a button going down and coming up rather than a key repeat.
      Keys.onPressed: function(event) {
        if (root.typing) return
        // On the cover, X is the only button that does anything: it starts.
        if (mm.arming) {
          if (event.key === Qt.Key_X) { mm.startArmed(); event.accepted = true }
          return
        }
        // On the shelf the same buttons move a selection and pick one, so the
        // whole console is usable without ever touching the mouse.
        if (!mm.playing) {
          if (mm.creating) return
          var n = mm.carts.length
          if (n === 0) return
          var s = buttonFor(event.key)
          if (s === 0)      root.shelfIndex = Math.max(0, root.shelfIndex - 1)
          else if (s === 1) root.shelfIndex = Math.min(n - 1, root.shelfIndex + 1)
          else if (s === 2) root.shelfIndex = Math.max(0, root.shelfIndex - root.shelfColumns)
          else if (s === 3) root.shelfIndex = Math.min(n - 1, root.shelfIndex + root.shelfColumns)
          else if (s === 4 || s === 5) {
            var pick = mm.carts[root.shelfIndex]
            if (pick) mm.arm(pick.id, pick.title)
          } else return
          event.accepted = true
          return
        }
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

            // Two images, shown alternately. A single Image reloading a data
            // uri thirty times a second is blank for part of every frame, and
            // that is the flicker: the fix is to decode into the hidden one and
            // only then swap which is visible, so something complete is always
            // on screen.
            Item {
              id: screen
              anchors.centerIn: parent
              width: 128 * screenBox.pixelScale
              height: width

              readonly property string src: mm.playing
                ? (mm.frame !== "" ? "data:image/png;base64," + mm.frame : "")
                : (mm.coverFor(mm.armedId) !== ""
                   ? "data:image/png;base64," + mm.coverFor(mm.armedId) : "")

              property bool showA: true

              onSrcChanged: {
                if (src === "") { pageA.source = ""; pageB.source = ""; return }
                // asynchronous:false, so the assignment has finished decoding by
                // the time the next line runs.
                if (showA) { pageB.source = src; showA = false }
                else       { pageA.source = src; showA = true }
              }

              Image {
                id: pageA
                anchors.fill: parent
                visible: screen.showA
                // 128 pixels blown up: never interpolate, or the whole point of
                // an eight-colour console is lost to a blur.
                smooth: false
                mipmap: false
                fillMode: Image.Stretch
                cache: false
                asynchronous: false
              }

              Image {
                id: pageB
                anchors.fill: parent
                visible: !screen.showA
                smooth: false
                mipmap: false
                fillMode: Image.Stretch
                cache: false
                asynchronous: false
              }
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

            // Brand, and the size control under it. A widget you can only
            // resize from a settings page is one you resize once and never
            // again — so it is a button on the console, where your hand is.
            Column {
              anchors.centerIn: parent
              spacing: Style.space(3)

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "MICROMACHEE"
                color: mm.shellDim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 2
                opacity: 0.7
              }

              Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.space(4)

                Repeater {
                  model: [
                    { "label": "−", "step": -1 },
                    { "label": "+", "step": 1 }
                  ]
                  delegate: Rectangle {
                    required property var modelData
                    readonly property bool canDo:
                      mm.scale + modelData.step >= 2 && mm.scale + modelData.step <= 6
                    width: Style.space(16)
                    height: Style.space(14)
                    radius: Style.space(3)
                    color: "transparent"
                    border.width: 1
                    border.color: mm.shellDim
                    opacity: canDo ? 0.8 : 0.25

                    Text {
                      anchors.centerIn: parent
                      text: modelData.label
                      color: mm.shellDim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                    }

                    MouseArea {
                      anchors.fill: parent
                      enabled: parent.canDo
                      cursorShape: Qt.PointingHandCursor
                      onClicked: mm.setScale(mm.scale + modelData.step)
                    }
                  }
                }
              }
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

        // ── a game you made ─────────────────────────────────────────────
        // Only on the cover, not mid-play: this is where you look at it and
        // decide, rather than something to fumble at while it is running.
        Column {
          visible: mm.arming && mm.isDraft(mm.armedId)
          width: parent.width
          spacing: Style.space(6)

          Text {
            width: parent.width
            text: "Not on the shelf yet. Say what to change, or keep it."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Rectangle {
            width: parent.width
            height: Style.space(26)
            radius: Style.cornerRadius
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
            border.width: reviseField.activeFocus ? 1 : 0
            border.color: mm.shellAccent

            TextInput {
              id: reviseField
              anchors.fill: parent
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              verticalAlignment: TextInput.AlignVCenter
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              selectByMouse: true
              enabled: !mm.working
              onAccepted: if (text !== "") { mm.revise(mm.armedId, text); text = "" }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: reviseField.text === ""
                text: mm.working && mm.makeStatus !== "" ? mm.makeStatus : "make it harder"
                color: root.dim
                font: reviseField.font
              }
            }
          }

          RowLayout {
            width: parent.width
            spacing: Style.space(6)

            Rectangle {
              Layout.fillWidth: true
              height: Style.space(26)
              radius: Style.cornerRadius
              color: "transparent"
              border.width: 1
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
              opacity: (!mm.working && reviseField.text !== "") ? 1 : 0.4

              Text {
                anchors.centerIn: parent
                text: "CHANGE IT"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              MouseArea {
                anchors.fill: parent
                enabled: !mm.working && reviseField.text !== ""
                cursorShape: Qt.PointingHandCursor
                onClicked: { mm.revise(mm.armedId, reviseField.text); reviseField.text = "" }
              }
            }

            Rectangle {
              Layout.fillWidth: true
              height: Style.space(26)
              radius: Style.cornerRadius
              color: mm.shellAccent
              opacity: mm.working ? 0.4 : 1

              Text {
                anchors.centerIn: parent
                text: "KEEP IT"
                color: mm.shellBezel
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }

              MouseArea {
                anchors.fill: parent
                enabled: !mm.working
                cursorShape: Qt.PointingHandCursor
                onClicked: mm.publishDraft(mm.armedId)
              }
            }

            Rectangle {
              width: Style.space(30)
              height: Style.space(26)
              radius: Style.cornerRadius
              color: "transparent"
              border.width: 1
              border.color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.45)
              opacity: mm.working ? 0.4 : 1

              Text {
                anchors.centerIn: parent
                text: "✕"
                color: root.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              MouseArea {
                anchors.fill: parent
                enabled: !mm.working
                cursorShape: Qt.PointingHandCursor
                onClicked: mm.discardDraft(mm.armedId)
              }
            }
          }
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

        // ── make one ────────────────────────────────────────────────────
        Rectangle {
          visible: !mm.playing && !mm.arming && !mm.creating && mm.installed
          width: parent.width
          height: Style.space(30)
          radius: Style.cornerRadius
          color: makeHover.containsMouse
            ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.13)
            : "transparent"
          border.width: 1
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)

          Text {
            anchors.centerIn: parent
            text: "+  MAKE A GAME"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          MouseArea {
            id: makeHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              mm.openCreate()
              Qt.callLater(function() { nameField.forceActiveFocus() })
            }
          }
        }

        Column {
          visible: mm.creating
          width: parent.width
          spacing: Style.space(8)

          Text {
            width: parent.width
            text: "Say what the game is. It gets written, checked, and if it does "
                  + "not run it gets fixed and checked again."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Rectangle {
            width: parent.width
            height: Style.space(26)
            radius: Style.cornerRadius
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
            border.width: nameField.activeFocus ? 1 : 0
            border.color: mm.shellAccent

            TextInput {
              id: nameField
              anchors.fill: parent
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              verticalAlignment: TextInput.AlignVCenter
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              selectByMouse: true
              enabled: !mm.working
              maximumLength: 24
              onAccepted: promptField.forceActiveFocus()

              Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: nameField.text === ""
                text: "name"
                color: root.dim
                font: nameField.font
              }
            }
          }

          Rectangle {
            width: parent.width
            height: Style.space(58)
            radius: Style.cornerRadius
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
            border.width: promptField.activeFocus ? 1 : 0
            border.color: mm.shellAccent

            TextEdit {
              id: promptField
              anchors.fill: parent
              anchors.margins: Style.space(8)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              selectByMouse: true
              enabled: !mm.working
              wrapMode: TextEdit.Wrap

              Text {
                visible: promptField.text === ""
                text: "a snake that speeds up as it eats"
                color: root.dim
                font: promptField.font
              }
            }
          }

          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            Rectangle {
              Layout.fillWidth: true
              height: Style.space(28)
              radius: Style.cornerRadius
              color: mm.working
                ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
                : mm.shellAccent
              opacity: (nameField.text !== "" && promptField.text !== "") || mm.working ? 1 : 0.4

              Text {
                anchors.centerIn: parent
                text: mm.working ? (mm.makeStatus !== "" ? mm.makeStatus.toUpperCase() : "WORKING")
                                 : "MAKE IT"
                color: mm.working ? root.foreground : mm.shellBezel
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: !mm.working
              }

              MouseArea {
                anchors.fill: parent
                enabled: !mm.working && nameField.text !== "" && promptField.text !== ""
                cursorShape: Qt.PointingHandCursor
                onClicked: mm.make(nameField.text, promptField.text)
              }
            }

            Rectangle {
              width: Style.space(64)
              height: Style.space(28)
              radius: Style.cornerRadius
              color: "transparent"
              border.width: 1
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)

              Text {
                anchors.centerIn: parent
                text: "CANCEL"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              MouseArea {
                anchors.fill: parent
                enabled: !mm.working
                cursorShape: Qt.PointingHandCursor
                onClicked: mm.closeCreate()
              }
            }
          }
        }

        Text {
          visible: !mm.playing && !mm.arming && !mm.creating && mm.carts.length > 0
          width: parent.width
          text: "ARROWS OR WASD TO CHOOSE · Z OR X TO PICK · T THEME"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          horizontalAlignment: Text.AlignHCenter
        }

        // ── the shelf, as a grid ────────────────────────────────────────
        // Covers are the point, so they get the room. It is navigable with the
        // same buttons a game uses — arrows or WASD to move, O or X to pick —
        // because reaching for the mouse in a console is a jarring thing to
        // have to do.
        Grid {
          visible: !mm.playing && !mm.arming && !mm.creating
          width: parent.width
          columns: root.shelfColumns
          spacing: Style.space(6)

          Repeater {
            model: (mm.playing || mm.arming || mm.creating) ? [] : mm.carts

            delegate: Item {
              required property var modelData
              required property int index
              readonly property bool picked: index === root.shelfIndex
              width: (body.width - Style.space(6) * (root.shelfColumns - 1)) / root.shelfColumns
              height: width + Style.space(16)

              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius
                color: picked || tileHover.containsMouse
                  ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
                  : "transparent"
                border.width: picked ? 1 : 0
                border.color: mm.shellAccent
              }

              Rectangle {
                id: art
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.topMargin: Style.space(3)
                width: parent.width - Style.space(6)
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

              Text {
                anchors.top: art.bottom
                anchors.topMargin: 1
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - Style.space(6)
                horizontalAlignment: Text.AlignHCenter
                text: modelData.title
                color: modelData.draft === true ? mm.shellAccent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              MouseArea {
                id: tileHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.shelfIndex = index
                onClicked: {
                  root.shelfIndex = index
                  mm.arm(modelData.id, modelData.title)
                  Qt.callLater(function() { keys.forceActiveFocus() })
                }
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
