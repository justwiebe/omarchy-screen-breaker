import QtQuick

// One melting column: a thin strip of the screenshot that slides down from
// where it started. The Image shares the screenshot's texture, so hundreds of
// drips cost little more than their geometry.
Item {
  id: drip

  property url source
  property real startY: 0
  property real length: 40
  property real offset: 0
  property real speed: 100
  property real life: 2
  readonly property bool active: life > 0

  y: startY
  height: length + offset
  clip: true

  // Returns false once the drip has stopped moving.
  function step(dt) {
    if (life <= 0) return false
    life -= dt
    speed *= Math.pow(0.995, dt * 60)
    offset += Math.max(0.5, speed * dt)
    return true
  }

  Image {
    source: drip.source
    x: -drip.x
    y: -drip.startY + drip.offset
    width: drip.parent ? drip.parent.width : 0
    height: drip.parent ? drip.parent.height : 0
    cache: true
    smooth: false
  }
}
