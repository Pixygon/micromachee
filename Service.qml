// The console's wiring: the shelf, and the running game.
//
// Two processes, and they are deliberately different shapes.
//
//   `status`  — short-lived, polled. What carts exist, what the records are.
//   `browse`  — long-lived. The shelf, drawn by the console itself, in the same
//               128×128 and driven by the same six buttons. It prints `G <id>`
//               when the player picks something and then gets out of the way.
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
  /// Where the helper wrote the generated sound bank, and whether it plays.
  property string soundsDir: ""
  property bool muted: false
  property bool paused: false
  property color shellBody: "#000000"
  property color shellBezel: "#000000"
  property color shellText: "#fff1e8"
  property color shellDim: "#b3a9a2"
  property color shellAccent: "#ff004d"
  // The screen this theme is shown on (scanline/bloom/aberration/noise/
  // vignette/grid/persist, each 0..1) — read by the panel's shader.
  property var fx: ({})

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
  /// The shelf is a program the console runs, so it is on screen like a game.
  readonly property bool browsing: browseProcess.running

  /// Whether the panel is open. Nothing draws frames behind a closed bar.
  property bool active: false
  /// Set across the moment between stopping the shelf and starting a game, so
  /// a process exiting in that gap does not start the shelf back up underneath.
  property bool starting: false

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

  /// `intro` plays the opening titles. Only the panel opening passes it: the
  /// shelf also restarts when you leave a game or change the tongue, and titles
  /// on the way out of a game are not a welcome, they are a wait.
  function startBrowse(intro) {
    if (!active || starting || creating || playing || armedId !== "") return
    if (browseProcess.running) return
    frame = ""
    held = 0
    paused = false
    browseProcess.command = intro === true ? [bin, "browse", "--intro"] : [bin, "browse"]
    browseProcess.running = true
  }

  function stopBrowse() {
    if (!browseProcess.running) return
    try { browseProcess.write("Q\n") } catch (e) {}
    browseProcess.running = false
    frame = ""
  }

  /// The shelf reads the carts once, when it starts. Anything that changes what
  /// is on the shelf has to stand it up again.
  function refreshBrowse() {
    if (!browseProcess.running) return
    stopBrowse()
    Qt.callLater(function() { root.startBrowse() })
  }

  function openCreate() {
    creating = true
    makeStatus = ""
    lastError = ""
    disarm()
    stop()
    stopBrowse()
  }

  function closeCreate() {
    creating = false
    makeStatus = ""
    startBrowse()
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
    stopBrowse()
    armedId = id
    armedTitle = title
  }

  function disarm() {
    armedId = ""
    armedTitle = ""
    startBrowse()
  }

  function startArmed() {
    if (armedId === "") return
    var id = armedId
    var title = armedTitle
    disarm()
    play(id, title)
  }

  /// Pull the shelf. Without `update` this only fetches carts that are not here
  /// at all and counts the ones that have moved on; with it, it takes the new
  /// versions too and keeps the old ones as .lua.bak.
  ///
  /// This runs on its own when the panel opens, so a shelf is never quietly a
  /// release behind. Its failures are deliberately silent: being offline is not
  /// an error the person opening a games console needs told about.
  function syncShelf(update) {
    if (syncing) return
    syncing = true
    if (update === true) updatesReady = 0
    syncProcess.command = update === true ? [bin, "sync", "--update"] : [bin, "sync"]
    syncProcess.running = true
  }

  function refresh() {
    if (statusProcess.running) return
    statusProcess.command = [bin, "status"]
    statusProcess.running = true
  }

  function play(id, title) {
    starting = true
    stop()
    stopBrowse()
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
    starting = false
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
    } else if (browseProcess.running) {
      // The shelf takes a palette live for the same reason a game does.
      try { browseProcess.write("T " + next + "\n") } catch (e) {}
      refresh()
    } else {
      themeProcess.command = [bin, "theme", next]
      themeProcess.running = true
    }
  }

  /// Every word the console prints goes through the helper, so a whole change
  /// of language is one flag there and nothing at all here.
  /// Play one of the eight. Silent, rather than broken, if the loader failed.
  function beep(n) {
    if (soundLoader.item) soundLoader.item.play(n)
  }

  function toggleMute() {
    var next = !muted
    muted = next
    muteProcess.command = [bin, "mute", next ? "on" : "off"]
    muteProcess.running = true
  }

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
    if (paused) return
    if (!gameProcess.running && !browseProcess.running) return
    paused = true
    held = 0
    try { if (gameProcess.running) gameProcess.write("P\n") } catch (e) {}
    try { if (browseProcess.running) browseProcess.write("P\n") } catch (e) {}
  }

  function resume() {
    if (!paused) return
    paused = false
    try { if (gameProcess.running) gameProcess.write("R\n") } catch (e) {}
    try { if (browseProcess.running) browseProcess.write("R\n") } catch (e) {}
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

  /// The same six bits go to whatever is on screen. The shelf and a game are
  /// the same kind of thing to this function, which is the point of the change.
  function setButton(bit, down) {
    var next = down ? (held | (1 << bit)) : (held & ~(1 << bit))
    if (next === held) return
    held = next
    var target = gameProcess.running ? gameProcess
               : (browseProcess.running ? browseProcess : null)
    if (target) {
      try { target.write("B " + held + "\n") } catch (e) {}
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
      root.soundsDir = String(s.sounds || "")
      root.muted = s.muted === true
      if (s.shell) {
        root.shellBody = s.shell.body || root.shellBody
        root.shellBezel = s.shell.bezel || root.shellBezel
        root.shellText = s.shell.text || root.shellText
        root.shellDim = s.shell.dim || root.shellDim
        root.shellAccent = s.shell.accent || root.shellAccent
      }
      if (s.fx) root.fx = s.fx
    }
  }

  // Sound is optional in the strongest sense: if QtMultimedia is missing this
  // Loader fails, `item` stays null, and the console is quiet. Importing it in
  // the panel instead would have taken the whole widget down with it.
  Loader {
    id: soundLoader
    source: "Sound.qml"
    onLoaded: if (item) item.dir = root.soundsDir
  }

  Connections {
    target: root
    function onSoundsDirChanged() {
      if (soundLoader.item) soundLoader.item.dir = root.soundsDir
    }
  }

  Process {
    id: muteProcess
    running: false
    command: []
    onExited: function() {
      root.refresh()
      // The helper decides whether to send sound at all, so a running game has
      // to be told. It is one flag on the next frame either way.
      root.refreshBrowse()
    }
  }

  Process {
    id: tongueProcess
    running: false
    command: []
    onExited: function() {
      root.refresh()
      root.loadCovers()
      root.refreshBrowse()   // the shelf's own labels are in the old tongue too
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
      root.refreshBrowse()
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
    id: syncProcess
    running: false
    command: []
    stdout: SplitParser {
      onRead: function(line) {
        var s = String(line)
        // "3 cart(s) here differ from the shelf: picross, snake, rogue"
        var m = s.match(/^(\d+) cart\(s\) here differ/)
        if (m) root.updatesReady = parseInt(m[1], 10) || 0
        if (s.indexOf(" new,") >= 0) {
          var got = s.match(/^(\d+) new/)
          if (got && parseInt(got[1], 10) > 0) root.gotNewCarts = true
          var upd = s.match(/(\d+) updated/)
          if (upd && parseInt(upd[1], 10) > 0) root.gotNewCarts = true
        }
      }
    }
    stderr: StdioCollector { id: syncErr; waitForEnd: true }
    onExited: function() {
      root.syncing = false
      root.refresh()
      if (root.gotNewCarts) {
        root.gotNewCarts = false
        root.loadCovers()
        root.refreshBrowse()      // the shelf read its carts when it started
      }
    }
  }

  Process {
    id: browseProcess
    running: false
    command: []
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(line) {
        var s = String(line)
        if (s.length < 2) return
        var kind = s.charAt(0)
        if (kind === "F") root.frame = s.substring(2)
        else if (kind === "A") root.beep(parseInt(s.substring(2), 10) || 0)
        else if (kind === "M") {
          // The last tile on the shelf is not a cart. It asks for this.
          root.openCreate()
        } else if (kind === "G") {
          var id = s.substring(2)
          var title = id
          for (var i = 0; i < root.carts.length; i++)
            if (root.carts[i].id === id) title = String(root.carts[i].title || id)
          // A draft is not ready to just start: picking one opens the panel
          // where you say what to change, publish it, or throw it away.
          if (root.isDraft(id)) root.arm(id, title)
          else root.play(id, title)
        }
      }
    }
    stderr: StdioCollector { id: browseErr; waitForEnd: true }
    onExited: function() {
      // Only ever restarts itself when nothing else wants the screen; the
      // guards live in startBrowse so every caller gets the same answer.
      Qt.callLater(function() { root.startBrowse() })
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
        else if (kind === "A") root.beep(parseInt(s.substring(2), 10) || 0)
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
      root.startBrowse()
    }
  }
}
