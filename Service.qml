// The state behind the widget.
//
// Everything real happens in the `omarchy-micromachee` binary. This file
// asks it what is true and turns the answer into properties.
//
// That split is the point of this template. QML cannot be unit-tested without a
// compositor, so anything you put here you will only ever verify by looking at
// it. Put the logic in the helper, where `cargo test` can reach it, and keep
// this layer dumb enough to be obviously correct.

import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  // Settings the user set in Omarchy's plugin config (see manifest.json).
  property var settings: ({})

  property bool installed: true
  property bool ready: false
  property string headline: ""
  property string actionStatus: ""
  property string lastError: ""

  readonly property bool busy: statusProcess.running || actionProcess.running
  readonly property int pollIntervalSec: {
    var n = parseInt(String(settings && settings.pollIntervalSec !== undefined ? settings.pollIntervalSec : 5), 10)
    if (!isFinite(n)) n = 5
    return Math.max(1, Math.min(60, n))
  }

  function refresh() {
    if (statusProcess.running) return
    statusProcess.command = ["omarchy-micromachee", "status"]
    statusProcess.running = true
  }

  function applyStatus(raw) {
    var s = {}
    try { s = JSON.parse(String(raw || "{}")) } catch (e) { return }
    ready = s.ready === true
    headline = String(s.headline || "")
  }

  // Every button is this shape: run the helper, say what happened, look again.
  // Nothing in the UI pretends to know the outcome before it lands.
  function act(args, sayingWhat) {
    if (actionProcess.running) return
    actionStatus = sayingWhat || ""
    lastError = ""
    actionProcess.command = ["omarchy-micromachee"].concat(args)
    actionProcess.running = true
  }

  Timer {
    interval: root.pollIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: statusClear
    interval: 2400
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    stderr: StdioCollector { id: statusErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.installed = true
        root.applyStatus(statusOut.text)
      } else if (String(statusErr.text).indexOf("No such file") >= 0) {
        // Not an error worth shouting about — the panel explains how to fix it.
        root.installed = false
      }
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.lastError = ""
        root.actionStatus = ""
      } else {
        // The helper's last stderr line is the one written for a person.
        var lines = String(actionErr.text || "").split("\n").filter(function(l) { return l.trim() !== "" })
        root.lastError = lines.length ? lines[lines.length - 1].replace(/^✗ /, "") : "that didn't work"
        root.actionStatus = ""
      }
      root.refresh()
    }
  }
}
