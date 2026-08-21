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
  /// Screen pixels per console pixel. Lives in the helper so the buttons on the
  /// console can change it, and so it survives a reload.
  property int scale: 3
  /// "plain", or "ydrast" if somebody found it.
  property string tongue: "plain"
  property bool paused: false
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

  // Cover art, id -> base64 PNG, fetched once when the shelf is opened rather
  // than on the poll timer: it is ~10K a cart, and `status` has to stay cheap.
  property var covers: ({})

  // A cart chosen but not yet started. The cover gets a moment on screen and
  // the player gets a beat to put their hands on the keys.
  property string armedId: ""
  property string armedTitle: ""

  // Making a game. `makeStatus` is the helper's last progress line, shown while
  // a request that takes tens of seconds is in flight.
  property bool creating: false
  property bool working: false
  property string makeStatus: ""
  property string madeId: ""

  readonly property bool playing: playingId !== ""
  readonly property bool arming: armedId !== "" && playingId === ""

  function isDraft(id) {
    for (var i = 0; i < carts.length; i++)
      if (carts[i].id === id) return carts[i].draft === true
    return false
  }

  function aboutFor(id) {
    for (var i = 0; i < carts.length; i++)
      if (carts[i].id === id) return String(carts[i].about || "")
    return ""
  }

  function bestFor(id) {
    for (var i = 0; i < carts.length; i++)
      if (carts[i].id === id) return Number(carts[i].best || 0)
    return 0
  }

  function coverFor(id) {
    return covers && covers[id] !== undefined ? covers[id] : ""
  }
  readonly property string bin: "omarchy-micromachee"

  // Button bits: 0 left, 1 right, 2 up, 3 down, 4 O, 5 X — the same order the
  // helper and every cart use.
  property int held: 0

  function openCreate() {
    creating = true
    makeStatus = ""
    lastError = ""
    disarm()
    stop()
  }

  function closeCreate() {
    creating = false
    makeStatus = ""
  }

  // Both making and revising speak the same little protocol on stdout:
  //   P <what is happening>   D <draft id, done>   E <what went wrong>
  function make(name, prompt) {
    if (working) return
    working = true
    madeId = ""
    lastError = ""
    makeStatus = "starting"
    makeProcess.command = [bin, "make", String(name), String(prompt)]
    makeProcess.running = true
  }

  function revise(id, prompt) {
    if (working) return
    working = true
    lastError = ""
    makeStatus = "starting"
    makeProcess.command = [bin, "revise", String(id), String(prompt)]
    makeProcess.running = true
  }

  function publishDraft(id) {
    if (working) return
    working = true
    actProcess.command = [bin, "publish", String(id)]
    actProcess.running = true
  }

  function discardDraft(id) {
    if (working) return
    working = true
    disarm()
    actProcess.command = [bin, "discard", String(id)]
    actProcess.running = true
  }

  function loadCovers() {
    if (coversProcess.running) return
    coversProcess.command = [bin, "covers"]
    coversProcess.running = true
  }

  function arm(id, title) {
    lastError = ""
    armedId = id
    armedTitle = title
  }

  function disarm() {
    armedId = ""
    armedTitle = ""
  }

  function startArmed() {
    if (armedId === "") return
    var id = armedId
    var title = armedTitle
    disarm()
    play(id, title)
  }

  function refresh() {
    if (statusProcess.running) return
    statusProcess.command = [bin, "status"]
    statusProcess.running = true
  }

  function play(id, title) {
    stop()
    paused = false
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
    themeId = next                       // show it at once; status confirms it
    if (gameProcess.running) {
      // Live. The old code restarted the cart to pick up the palette, which
      // meant killing this process and starting another on the same Process
      // object — and the dying one's `onExited` then wiped the new one's state,
      // dropping you to the shelf and leaving everything stuck there. A palette
      // is eight bytes in the next frame's PLTE; the cart never needs to know.
      try { gameProcess.write("T " + next + "\n") } catch (e) {}
      refresh()
    } else {
      themeProcess.command = [bin, "theme", next]
      themeProcess.running = true
    }
  }

  /// Every word the console prints goes through the helper, so a whole change
  /// of language is one flag there and nothing at all here.
  function toggleTongue() {
    var next = tongue === "ydrast" ? "plain" : "ydrast"
    tongue = next
    tongueProcess.command = [bin, "tongue", next]
    tongueProcess.running = true
  }

  function setScale(n) {
    var want = Math.max(2, Math.min(6, n))
    if (want === scale) return
    scale = want                          // no wait for the round trip
    scaleProcess.command = [bin, "scale", String(want)]
    scaleProcess.running = true
  }

  /// Closing the panel pauses; it does not throw the game away.
  function pause() {
    if (!gameProcess.running || paused) return
    paused = true
    held = 0
    try { gameProcess.write("P\n") } catch (e) {}
  }

  function resume() {
    if (!gameProcess.running || !paused) return
    paused = false
    try { gameProcess.write("R\n") } catch (e) {}
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
    disarm()
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
      root.scale = Number(s.scale || 3)
      root.tongue = String(s.tongue || "plain")
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
    id: tongueProcess
    running: false
    command: []
    onExited: function() {
      root.refresh()
      root.loadCovers()
      // A running cart is printing in the old tongue; restart it so the change
      // is visible at once. Safe here — unlike the theme, this one is rare.
      if (root.playing) {
        var id = root.playingId, title = root.playingTitle
        Qt.callLater(function() { root.stop(); root.play(id, title) })
      }
    }
  }

  Process {
    id: scaleProcess
    running: false
    command: []
    onExited: function() { root.refresh() }
  }

  Process {
    id: themeProcess
    running: false
    command: []
    onExited: function() {
      root.refresh()
      root.loadCovers()   // the covers are drawn in the palette too
    }
  }

  Process {
    id: makeProcess
    running: false
    command: []
    // Line by line, because the whole point is showing progress during a wait.
    stdout: SplitParser {
      onRead: function(line) {
        var s = String(line)
        if (s.length < 2) return
        var kind = s.charAt(0)
        if (kind === "P") root.makeStatus = s.substring(2)
        else if (kind === "D") root.madeId = s.substring(2)
        else if (kind === "E") root.lastError = s.substring(2)
      }
    }
    stderr: StdioCollector { id: makeErr; waitForEnd: true }
    onExited: function(exitCode) {
      root.working = false
      if (exitCode !== 0 && root.lastError === "") {
        var err = String(makeErr.text || "").trim()
        var lines = err.split("\n").filter(function(l) { return l.trim() !== "" })
        root.lastError = lines.length ? lines[lines.length - 1].replace(/^✗ /, "") : "that did not work"
      }
      root.makeStatus = ""
      root.refresh()
      root.loadCovers()
      // A game that came out works: show it, with its cover, ready to start.
      if (exitCode === 0 && root.madeId !== "") {
        root.closeCreate()
        for (var i = 0; i < root.carts.length; i++)
          if (root.carts[i].id === root.madeId) root.arm(root.madeId, root.carts[i].title)
        if (root.armedId === "") root.arm(root.madeId, root.madeId)
      }
    }
  }

  Process {
    id: actProcess
    running: false
    command: []
    stdout: StdioCollector { id: actOut; waitForEnd: true }
    stderr: StdioCollector { id: actErr; waitForEnd: true }
    onExited: function(exitCode) {
      root.working = false
      if (exitCode !== 0) {
        var err = String(actErr.text || "").trim()
        var lines = err.split("\n").filter(function(l) { return l.trim() !== "" })
        root.lastError = lines.length ? lines[lines.length - 1].replace(/^✗ /, "") : "that did not work"
      }
      root.refresh()
      root.loadCovers()
    }
  }

  Process {
    id: coversProcess
    running: false
    command: []
    stdout: StdioCollector { id: coversOut; waitForEnd: true }
    stderr: StdioCollector { id: coversErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      // A cart whose cover will not render is simply absent from the map, and
      // the shelf falls back to drawing its initial instead of nothing.
      try { root.covers = JSON.parse(String(coversOut.text || "{}")) } catch (e) {}
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
