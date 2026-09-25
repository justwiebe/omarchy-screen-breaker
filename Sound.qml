import Quickshell
import Quickshell.Io
import QtQuick

// Sound effects through PipeWire's pw-play (Qt Multimedia isn't part of a
// stock Omarchy install). One-shots are fire-and-forget processes; loops are
// long-running processes started while a tool is held and killed on release.
Item {
  id: sound

  property string dir: ""
  property bool muted: false
  property real volume: 0.8

  function play(name, level) {
    if (muted || !dir) return
    var v = (level === undefined ? 1 : level) * volume
    Quickshell.execDetached(["pw-play", "--volume", v.toFixed(2), dir + "/" + name + ".wav"])
  }

  function setLoop(name, on) {
    var loop = loops[name]
    if (!loop || loop.wanted === on) return
    loop.wanted = on
    if (on && !muted) loop.running = true
    else if (!on) loop.running = false
  }

  function stopAll() {
    for (var name in loops) setLoop(name, false)
  }

  function toggleMute() {
    muted = !muted
    for (var name in loops) {
      var loop = loops[name]
      loop.running = loop.wanted && !muted
    }
    return muted
  }

  readonly property var loops: ({
    flame: flameLoop, laser: laserLoop, melt: meltLoop, fuse: fuseLoop, smg: smgLoop
  })

  component Loop: Process {
    property string name
    property real level: 1
    property bool wanted: false
    command: ["pw-play", "--volume", (level * sound.volume).toFixed(2), sound.dir + "/" + name + "-loop.wav"]
    // Clips are a few seconds long; start the next pass while still held.
    onExited: if (wanted && !sound.muted) Qt.callLater(function() { running = true })
  }

  Loop { id: flameLoop; name: "flame"; level: 0.9 }
  Loop { id: laserLoop; name: "laser"; level: 0.7 }
  Loop { id: meltLoop; name: "melt"; level: 0.8 }
  Loop { id: fuseLoop; name: "fuse"; level: 0.5 }
  Loop { id: smgLoop; name: "smg"; level: 0.9 }
}
