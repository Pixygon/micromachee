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

  /// Whether the card is up over the cover. X plays; O is the other one.
  property bool showInfo: false

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
      mm.active = true
      mm.resume()              // a closed panel paused it; pick it back up
      mm.startBrowse(true)     // and the shelf, with its titles, is what opens
      mm.syncShelf(false)      // and it checks the shelf while you read them
      Qt.callLater(function() { keys.forceActiveFocus() })
    } else {
      // Not `stop()`. Closing the bar to look at something else should cost you
      // a moment, not the run you were in the middle of.
      mm.active = false
      mm.pause()
    }
  }

  Service {
    id: mm
    settings: root.settings
  }

  Connections {
    target: mm
    function onArmedIdChanged() { root.showInfo = false }
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
    textFormat: Text.PlainText
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
        if (root.typing || mm.creating) return
        // On the cover, X is the only button that does anything: it starts.
        if (mm.arming) {
          if (event.key === Qt.Key_X) { mm.startArmed(); event.accepted = true }
          else if (event.key === Qt.Key_Z || event.key === Qt.Key_Space) {
            root.showInfo = !root.showInfo
            event.accepted = true
          }
          return
        }
        var b = buttonFor(event.key)
        if (b < 0) return
        // The shelf is a program the console runs, so its buttons are the
        // console's buttons: nothing here decides what they mean any more.
        //
        // That is also why the button sequence that used to reach the Ydrast
        // tongue is gone rather than merely broken: on this shelf X opens the
        // info card and O starts a game, so the last two presses of it did
        // something else long before the sequence could finish. It is the dot
        // on the console body now.
        mm.setButton(b, true)
        event.accepted = true
      }
      Keys.onReleased: function(event) {
        if (root.typing || mm.creating || mm.arming) return
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
          visible: mm.playing || mm.arming || mm.browsing
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

              // The shelf and a game arrive the same way — as frames — so this
              // only has to know about the one case that does not: a chosen
              // cart sitting on its cover, waiting to be started.
              readonly property string src: mm.arming
                ? (mm.coverFor(mm.armedId) !== ""
                   ? "data:image/png;base64," + mm.coverFor(mm.armedId) : "")
                : (mm.frame !== "" ? "data:image/png;base64," + mm.frame : "")

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
              visible: (mm.playing || mm.browsing) && mm.frame === "" && mm.lastError === ""
              text: "LOADING"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            // ── what this game is ─────────────────────────────────────────
            Rectangle {
              visible: mm.arming && root.showInfo
              anchors.fill: screen
              color: Qt.rgba(0, 0, 0, 0.93)

              Column {
                anchors.centerIn: parent
                width: parent.width - Style.space(16)
                spacing: Style.space(6)

                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: mm.armedTitle
                  textFormat: Text.PlainText
                  color: mm.shellText
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  wrapMode: Text.WordWrap
                }
                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: mm.aboutFor(mm.armedId)
                  textFormat: Text.PlainText
                  color: mm.shellDim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                }
                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  visible: Number(mm.bestFor(mm.armedId)) > 0
                  text: "BEST " + mm.bestFor(mm.armedId)
                  textFormat: Text.PlainText
                  color: mm.shellAccent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: "O CLOSES · X PLAYS"
                  color: mm.shellDim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  opacity: 0.6
                }
              }

              MouseArea {
                anchors.fill: parent
                onClicked: root.showInfo = false
              }
            }

            // ── press X ───────────────────────────────────────────────────
            Rectangle {
              visible: mm.arming && !root.showInfo
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
            height: Math.round(Style.space(56) * pad.k)

            // The console keeps its proportions at every size. Everything below
            // is a multiple of the same number the screen is drawn at, so
            // making the window bigger makes a bigger console rather than the
            // same buttons around a bigger screen.
            readonly property real k: screenBox.pixelScale / 3
            readonly property int cell: Math.round(Style.space(16) * pad.k)
            readonly property int round: Math.round(Style.space(22) * pad.k)
            readonly property int fs: Math.max(7, Math.round(Style.font.bodySmall * pad.k))

            Item {
              id: dpad
              anchors.left: parent.left
              anchors.leftMargin: Math.round(Style.space(10) * pad.k)
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
                  opacity: (mm.playing || mm.browsing) ? 1.0 : 0.45

                  Text {
                    anchors.centerIn: parent
                    text: modelData.key
                    textFormat: Text.PlainText
                    color: mm.shellBezel
                    font.family: root.fontFamily
                    font.pixelSize: pad.fs
                    font.bold: true
                  }

                  MouseArea {
                    anchors.fill: parent
                    enabled: mm.playing || mm.browsing
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
                font.pixelSize: pad.fs
                font.letterSpacing: 2 * pad.k
                opacity: 0.7
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "by Pixygon"
                color: mm.shellDim
                font.family: root.fontFamily
                font.pixelSize: pad.fs
                opacity: 0.55
              }

              Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Math.round(Style.space(4) * pad.k)

                // The Ydrast tongue. It used to be up-up-down-down-left-right
                // on the shelf, which stopped working the day the shelf moved
                // into the console and those buttons started games. So it is a
                // dot: unlabelled, easy to miss, and impossible to press by
                // accident — which is as close to a secret as a button gets.
                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.max(5, Math.round(6 * pad.k))
                  height: width
                  radius: width / 2
                  color: mm.tongue === "ydrast" ? mm.shellAccent : mm.shellDim
                  opacity: mm.tongue === "ydrast" ? 0.9 : 0.3

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mm.toggleTongue()
                  }
                }

                // Sound. A widget in a bar that makes noise you cannot stop is
                // a widget people uninstall, so this is one press away and the
                // helper honours it by not sending the sound at all.
                Rectangle {
                  width: Math.round(Style.space(16) * pad.k)
                  height: Math.round(Style.space(14) * pad.k)
                  radius: Math.round(Style.space(3) * pad.k)
                  color: "transparent"
                  border.width: 1
                  border.color: mm.shellDim
                  opacity: muteHover.containsMouse ? 1.0 : (mm.muted ? 0.35 : 0.8)

                  Text {
                    anchors.centerIn: parent
                    text: mm.muted ? "◌" : "◍"
                    textFormat: Text.PlainText
                    color: mm.shellDim
                    font.family: root.fontFamily
                    font.pixelSize: pad.fs
                  }

                  MouseArea {
                    id: muteHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mm.toggleMute()
                  }
                }

                // Fetch the shelf. It goes amber and carries a count when the
                // automatic check on opening found carts that have moved on,
                // so the one time you need this button it asks to be pressed.
                Rectangle {
                  width: Math.round(Style.space(20) * pad.k)
                  height: Math.round(Style.space(14) * pad.k)
                  radius: Math.round(Style.space(3) * pad.k)
                  color: "transparent"
                  border.width: 1
                  border.color: mm.updatesReady > 0 ? mm.shellAccent : mm.shellDim
                  opacity: mm.syncing ? 0.4 : (syncHover.containsMouse ? 1.0 : 0.8)

                  Text {
                    anchors.centerIn: parent
                    text: mm.updatesReady > 0 ? "↻" + mm.updatesReady : "↻"
                    textFormat: Text.PlainText
                    color: mm.updatesReady > 0 ? mm.shellAccent : mm.shellDim
                    font.family: root.fontFamily
                    font.pixelSize: pad.fs
                  }

                  MouseArea {
                    id: syncHover
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !mm.syncing
                    cursorShape: Qt.PointingHandCursor
                    // Always the updating one: pressing a button labelled with
                    // a count and having it not take those updates is a button
                    // that lied.
                    onClicked: mm.syncShelf(true)
                  }
                }

                // The colour mode lives here now rather than in a row of chrome
                // under the console. It is the palette itself on a button: the
                // four slots that change most, in the order the rank puts them.
                Rectangle {
                  visible: mm.themes.length > 1
                  width: Math.round(Style.space(26) * pad.k)
                  height: Math.round(Style.space(14) * pad.k)
                  radius: Math.round(Style.space(3) * pad.k)
                  color: "transparent"
                  border.width: 1
                  border.color: mm.shellDim
                  opacity: themeHover.containsMouse ? 1.0 : 0.8

                  Row {
                    anchors.centerIn: parent
                    spacing: 1
                    Repeater {
                      model: [mm.shellAccent, mm.shellText, mm.shellDim]
                      delegate: Rectangle {
                        required property var modelData
                        width: Math.max(3, Math.round(4 * pad.k))
                        height: Math.max(3, Math.round(8 * pad.k))
                        color: modelData
                      }
                    }
                  }

                  MouseArea {
                    id: themeHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mm.nextTheme()
                  }
                }

                Repeater {
                  model: [
                    { "label": "−", "step": -1 },
                    { "label": "+", "step": 1 }
                  ]
                  delegate: Rectangle {
                    required property var modelData
                    readonly property bool canDo:
                      mm.scale + modelData.step >= 2 && mm.scale + modelData.step <= 6
                    width: Math.round(Style.space(16) * pad.k)
                    height: Math.round(Style.space(14) * pad.k)
                    radius: Math.round(Style.space(3) * pad.k)
                    color: "transparent"
                    border.width: 1
                    border.color: mm.shellDim
                    opacity: canDo ? 0.8 : 0.25

                    Text {
                      anchors.centerIn: parent
                      text: modelData.label
                      textFormat: Text.PlainText
                      color: mm.shellDim
                      font.family: root.fontFamily
                      font.pixelSize: pad.fs
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
              anchors.rightMargin: Math.round(Style.space(10) * pad.k)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Math.round(Style.space(8) * pad.k)

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
                    opacity: (mm.playing || mm.browsing
                              || (mm.arming && modelData.bit === 5)) ? 1.0 : 0.45

                    Text {
                      anchors.centerIn: parent
                      text: modelData.name
                      textFormat: Text.PlainText
                      color: mm.shellBezel
                      font.family: root.fontFamily
                      font.pixelSize: Math.max(9, Math.round(Style.font.body * pad.k))
                      font.bold: true
                    }

                    MouseArea {
                      anchors.fill: parent
                      enabled: mm.playing || mm.browsing || (mm.arming && modelData.bit === 5)
                      onPressed: {
                        if (mm.arming) mm.startArmed()
                        else mm.setButton(modelData.bit, true)
                      }
                      // Release has to clear the bit wherever press set it, or
                      // clicking O on the shelf leaves it held down forever.
                      onReleased: if (mm.playing || mm.browsing) mm.setButton(modelData.bit, false)
                      onCanceled: if (mm.playing || mm.browsing) mm.setButton(modelData.bit, false)
                    }
                  }

                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.key
                    textFormat: Text.PlainText
                    color: mm.shellDim
                    font.family: root.fontFamily
                    font.pixelSize: pad.fs
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
            textFormat: Text.PlainText
            color: mm.shellText
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            Layout.fillWidth: true
            elide: Text.ElideRight
          }
          Text {
            visible: mm.playing
            text: mm.score + (mm.best > 0 ? "  /  BEST " + mm.best : "")
            textFormat: Text.PlainText
            color: mm.shellDim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
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
                textFormat: Text.PlainText
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



        Text {
          visible: mm.lastError !== ""
          width: parent.width
          text: mm.lastError
          textFormat: Text.PlainText
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
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
                textFormat: Text.PlainText
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

        // The shelf itself is gone from here on purpose. It is drawn by the
        // console now — `micromachee browse`, same 128x128, same six buttons —
        // so choosing a game is made of the same pixels as playing one.
      }
    }
  }
}
