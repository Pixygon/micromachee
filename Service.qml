// The console's wiring: the shelf, and the running game.
//
// Two processes, and they are deliberately different shapes.
//
//   `status`  — short-lived, polled. What carts exist, what the records are.
//   `play`    — long-lived, one per game. It prints a base64 PNG per line and
//               reads a button bitmask on stdin. It only exists while the panel
//               is open, because a game running behind a closed panel is a
//               background process burning CPU to draw frames nobody sees.
//
// Nothing here knows any rules of any game. It moves pixels one way and button
// bits the other.

import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var settings: ({})

  property bool installed: true
  property var carts: []
  property string lastId: ""

  // The shell travels with the palette, so the QML never picks a colour of its
  // own. A widget that themes half of itself looks worse than one that does not
  // theme at all.
  property string themeId: ""
  property var themes: []
  property color shellBody: "#000000"
  property color shellBezel: "#000000"
  property color shellText: "#fff1e8"
  property color shellDim: "#b3a9a2"
  property color shellAccent: "#ff004d"

  // While a cart is running
  property string playingId: ""
  property string playingTitle: ""
  property string frame: ""          // base64 PNG, one per line from the helper
  property int score: 0
  property int best: 0
  property string lastError: ""

  readonly property bool playing: playingId !== ""
  readonly property string bin: "omarchy-micromachee"

  // Button bits: 0 left, 1 right, 2 up, 3 down, 4 O, 5 X — the same order the
  // helper and every cart use.
  property int held: 0

  function refresh() {
    if (statusProcess.running) return
    statusProcess.command = [bin, "status"]
    statusProcess.running = true
  }

  function play(id, title) {
    stop()
    lastError = ""
    frame = ""
    score = 0
    held = 0
    playingId = id
    playingTitle = title
    for (var i = 0; i < carts.length; i++)
      if (carts[i].id === id) best = Number(carts[i].best || 0)
    gameProcess.command = [bin, "play", id]
    gameProcess.running = true
  }

  function nextTheme() {
    if (themes.length < 2) return
    var i = themes.indexOf(themeId)
    var next = themes[(i + 1) % themes.length]
    themeProcess.command = [bin, "theme", next]
    themeProcess.running = true
  }

  function stop() {
    if (gameProcess.running) {
      // Ask first: the helper exits its loop on `Q` and gets to write out the
      // high score properly. Killing the process would drop the last run.
      try { gameProcess.write("Q\n") } catch (e) {}
      gameProcess.running = false
    }
    playingId = ""
    playingTitle = ""
    frame = ""
    held = 0
    refresh()
  }

  function setButton(bit, down) {
    var next = down ? (held | (1 << bit)) : (held & ~(1 << bit))
    if (next === held) return
    held = next
    if (gameProcess.running) {
      try { gameProcess.write("B " + held + "\n") } catch (e) {}
    }
  }

  Timer {
    interval: 4000
    repeat: true
    running: !root.playing
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    stderr: StdioCollector { id: statusErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        if (String(statusErr.text).indexOf("No such file") >= 0) root.installed = false
        return
      }
      root.installed = true
      var s = {}
      try { s = JSON.parse(String(statusOut.text || "{}")) } catch (e) { return }
      root.carts = s.carts || []
      root.lastId = String(s.last || "")
      root.themeId = String(s.theme || "")
      root.themes = s.themes || []
      if (s.shell) {
        root.shellBody = s.shell.body || root.shellBody
        root.shellBezel = s.shell.bezel || root.shellBezel
        root.shellText = s.shell.text || root.shellText
        root.shellDim = s.shell.dim || root.shellDim
        root.shellAccent = s.shell.accent || root.shellAccent
      }
    }
  }

  Process {
    id: themeProcess
    running: false
    command: []
    onExited: function() {
      root.refresh()
      // A running cart is drawing with the old palette; restart it so the
      // change is visible immediately rather than at the next game.
      if (root.playing) {
        var id = root.playingId, title = root.playingTitle
        root.stop()
        root.play(id, title)
      }
    }
  }

  Process {
    id: gameProcess
    running: false
    command: []
    stdinEnabled: true
    // One line per frame, so the parser is a line splitter and the protocol
    // needs no framing of its own.
    stdout: SplitParser {
      onRead: function(line) {
        var s = String(line)
        if (s.length < 2) return
        var kind = s.charAt(0)
        if (kind === "F") root.frame = s.substring(2)
        else if (kind === "S") {
          root.score = parseInt(s.substring(2), 10) || 0
          if (root.score > root.best) root.best = root.score
        } else if (kind === "E") {
          root.lastError = s.substring(2)
        }
      }
    }
    stderr: StdioCollector { id: gameErr; waitForEnd: true }
    onExited: function(exitCode) {
      var err = String(gameErr.text || "").trim()
      if (exitCode !== 0 && root.lastError === "" && err !== "") {
        var lines = err.split("\n").filter(function(l) { return l.trim() !== "" })
        root.lastError = lines[lines.length - 1].replace(/^✗ /, "")
      }
      root.playingId = ""
      root.playingTitle = ""
      root.refresh()
    }
  }
}
