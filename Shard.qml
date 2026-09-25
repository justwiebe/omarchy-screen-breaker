import QtQuick
import QtQuick.Shapes

// A piece of glass that fell out. The polygon is in screen coordinates and
// filled with the screenshot at the same place, so it starts out looking
// exactly like the screen it came from, then spins and falls away.
Shape {
  id: shard

  property var poly: []
  property Item texture: null
  property real cx: 0
  property real cy: 0
  property real dx: 0
  property real dy: 0
  property real angle: 0
  property real vx: 0
  property real vy: 0
  property real spin: 0
  property real delay: 0

  anchors.fill: parent
  preferredRendererType: Shape.CurveRenderer

  transform: [
    Rotation { origin.x: shard.cx; origin.y: shard.cy; angle: shard.angle },
    Translate { x: shard.dx; y: shard.dy }
  ]

  // Returns false once the shard has fallen off the bottom of the screen.
  function step(dt, bottom) {
    if (delay > 0) { delay -= dt; return true }
    vy += 1400 * dt
    dx += vx * dt
    dy += vy * dt
    angle += spin * dt
    return cy + dy < bottom + 400
  }

  ShapePath {
    fillItem: shard.texture
    strokeColor: Qt.rgba(1, 1, 1, 0.7)
    strokeWidth: 1.2
    joinStyle: ShapePath.RoundJoin
    PathPolyline {
      path: shard.poly.map(function(p) { return Qt.point(p[0], p[1]) }).concat(
        shard.poly.length ? [Qt.point(shard.poly[0][0], shard.poly[0][1])] : [])
    }
  }
}
