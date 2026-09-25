import QtQuick

// Persistent damage (cracks, holes, scorch, dead pixels) drawn over the
// screenshot. The layer is split into tiles so a hit only repaints and
// re-uploads the few tiles it touches instead of one screen-sized canvas.
Item {
  id: grid

  readonly property int tileSize: 256
  readonly property int columns: Math.max(1, Math.ceil(width / tileSize))
  readonly property int rows: Math.max(1, Math.ceil(height / tileSize))

  // Queue `draw(ctx)` on every tile that `bounds` ({x, y, w, h}) overlaps.
  // `draw` works in layer coordinates; each tile translates for it.
  function paint(bounds, draw) {
    var c0 = Math.max(0, Math.floor(bounds.x / tileSize))
    var c1 = Math.min(columns - 1, Math.floor((bounds.x + bounds.w) / tileSize))
    var r0 = Math.max(0, Math.floor(bounds.y / tileSize))
    var r1 = Math.min(rows - 1, Math.floor((bounds.y + bounds.h) / tileSize))
    for (var r = r0; r <= r1; r++) {
      for (var c = c0; c <= c1; c++) {
        var tile = tiles.itemAt(r * columns + c)
        if (tile) tile.enqueue(draw)
      }
    }
  }

  function clear() {
    for (var i = 0; i < tiles.count; i++) {
      var tile = tiles.itemAt(i)
      if (tile) tile.wipe()
    }
  }

  Repeater {
    id: tiles
    model: grid.columns * grid.rows

    Canvas {
      required property int index
      property var queue: []
      property bool wipePending: false

      x: (index % grid.columns) * grid.tileSize
      y: Math.floor(index / grid.columns) * grid.tileSize
      width: grid.tileSize
      height: grid.tileSize

      function enqueue(draw) {
        queue.push(draw)
        requestPaint()
      }

      function wipe() {
        queue = []
        wipePending = true
        requestPaint()
      }

      onPaint: {
        var ctx = getContext("2d")
        if (wipePending) {
          ctx.reset()
          ctx.clearRect(0, 0, width, height)
          wipePending = false
        }
        var pending = queue
        queue = []
        for (var i = 0; i < pending.length; i++) {
          ctx.save()
          ctx.translate(-x, -y)
          pending[i](ctx)
          ctx.restore()
        }
      }
    }
  }
}
