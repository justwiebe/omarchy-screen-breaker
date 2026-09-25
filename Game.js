.pragma library

// Pure helpers for Screen Breaker: geometry for cracks and shards, and the
// Canvas drawing used by the damage layer, the cursor, and toolbar icons.
// Coordinates are logical (device-independent) pixels throughout.

function rand(a, b) { return a + Math.random() * (b - a) }
function randi(a, b) { return Math.floor(rand(a, b + 1)) }
function pick(arr) { return arr[Math.floor(Math.random() * arr.length)] }
function clamp(v, a, b) { return Math.max(a, Math.min(b, v)) }

// ---------------------------------------------------------------------------
// Geometry
// ---------------------------------------------------------------------------

// A crack is a set of jagged rays from the impact point plus partial rings
// between neighbouring rays. `marks[j]` indexes the ray vertex where ring j
// crosses it, so the cells between rays and rings can fall out as shards.
function makeCrack(cx, cy, opts) {
  var rays = opts.rays || 12, len = opts.len || 160, rings = opts.rings || 4
  var ringChance = opts.ringChance === undefined ? 0.55 : opts.ringChance
  var jag = opts.jag || 0.25
  var ringD = []
  for (var r = 1; r <= rings; r++) ringD.push(len * Math.pow(r / (rings + 1), 1.25) * rand(0.85, 1.1))

  var out = []
  var base = rand(0, Math.PI * 2)
  for (var i = 0; i < rays; i++) {
    var a = base + (i / rays) * Math.PI * 2 + rand(-0.3, 0.3) * (Math.PI * 2 / rays)
    var L = len * rand(0.55, 1.2)
    var pts = [[cx, cy]], marks = [0]
    var x = cx, y = cy, d = 0, ang = a, j = 0
    while (d < L) {
      var step = rand(5, 13)
      ang = a + clamp(ang - a + rand(-jag, jag), -0.45, 0.45)
      x += Math.cos(ang) * step; y += Math.sin(ang) * step; d += step
      pts.push([x, y])
      while (j < ringD.length && d >= ringD[j]) { marks.push(pts.length - 1); j++ }
    }
    out.push({ pts: pts, marks: marks })
  }

  var ringSegs = []
  for (var k = 1; k <= rings; k++) {
    for (var n = 0; n < rays; n++) {
      var r1 = out[n], r2 = out[(n + 1) % rays]
      if (r1.marks[k] === undefined || r2.marks[k] === undefined) continue
      if (Math.random() > ringChance * (1 - k / (rings + 2))) continue
      var p = r1.pts[r1.marks[k]], q = r2.pts[r2.marks[k]]
      var m = [(p[0] + q[0]) / 2 + rand(-4, 4), (p[1] + q[1]) / 2 + rand(-4, 4)]
      ringSegs.push([p, m, q])
    }
  }
  return { cx: cx, cy: cy, rays: out, ringSegs: ringSegs, len: len * 1.2 }
}

// Polygon for the cell between ray i and ray i+1, ring j and j+1.
function cellPolygon(crack, i, j) {
  var r1 = crack.rays[i], r2 = crack.rays[(i + 1) % crack.rays.length]
  if (r1.marks[j + 1] === undefined || r2.marks[j + 1] === undefined) return null
  var a = r1.pts.slice(r1.marks[j], r1.marks[j + 1] + 1)
  var b = r2.pts.slice(r2.marks[j], r2.marks[j + 1] + 1).reverse()
  return a.concat(b)
}

function bbox(poly) {
  var x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity
  for (var i = 0; i < poly.length; i++) {
    x0 = Math.min(x0, poly[i][0]); y0 = Math.min(y0, poly[i][1])
    x1 = Math.max(x1, poly[i][0]); y1 = Math.max(y1, poly[i][1])
  }
  return { x: x0, y: y0, w: x1 - x0, h: y1 - y0 }
}

function crackBounds(crack) {
  return { x: crack.cx - crack.len - 10, y: crack.cy - crack.len - 10, w: crack.len * 2 + 20, h: crack.len * 2 + 20 }
}

function circleBounds(x, y, r) { return { x: x - r, y: y - r, w: r * 2, h: r * 2 } }

// ---------------------------------------------------------------------------
// Damage drawing (onto the persistent damage layer)
// ---------------------------------------------------------------------------

function strokePath(ctx, pts, width) {
  ctx.beginPath()
  ctx.moveTo(pts[0][0], pts[0][1])
  for (var k = 1; k < pts.length; k++) ctx.lineTo(pts[k][0], pts[k][1])
  ctx.lineWidth = width
  ctx.stroke()
}

function tracePoly(ctx, poly) {
  ctx.beginPath()
  ctx.moveTo(poly[0][0], poly[0][1])
  for (var k = 1; k < poly.length; k++) ctx.lineTo(poly[k][0], poly[k][1])
  ctx.closePath()
}

function glow(ctx, x, y, r, inner, outer) {
  var g = ctx.createRadialGradient(x, y, 0, x, y, r)
  g.addColorStop(0, inner)
  g.addColorStop(1, outer)
  ctx.fillStyle = g
  ctx.fillRect(x - r, y - r, r * 2, r * 2)
}

function drawCrack(ctx, crack, weight) {
  weight = weight || 1
  ctx.lineCap = "round"
  ctx.lineJoin = "round"
  for (var i = 0; i < crack.rays.length; i++) {
    var pts = crack.rays[i].pts, n = pts.length, chunks = 4
    for (var c = 0; c < chunks; c++) {
      var seg = pts.slice(Math.floor(c * n / chunks), Math.floor((c + 1) * n / chunks) + 1)
      if (seg.length < 2) continue
      var w = (1.9 - c * 0.4) * weight
      ctx.strokeStyle = "rgba(0,0,0,0.55)"
      strokePath(ctx, seg, w + 0.6)
      ctx.save()
      ctx.translate(0.6, -0.6)
      ctx.strokeStyle = "rgba(255,255,255,0.75)"
      strokePath(ctx, seg, Math.max(0.35, w * 0.45))
      ctx.restore()
    }
  }
  for (var s = 0; s < crack.ringSegs.length; s++) {
    ctx.strokeStyle = "rgba(0,0,0,0.45)"
    strokePath(ctx, crack.ringSegs[s], 1.1 * weight)
    ctx.strokeStyle = "rgba(255,255,255,0.6)"
    strokePath(ctx, crack.ringSegs[s], 0.5 * weight)
  }
  glow(ctx, crack.cx, crack.cy, 13 * weight, "rgba(255,255,255,0.8)", "rgba(255,255,255,0)")
}

// What's left behind when a piece of glass falls out: a dead LCD patch.
function drawDeadPixels(ctx, poly, palette) {
  var b = bbox(poly)
  ctx.save()
  tracePoly(ctx, poly)
  ctx.clip()
  ctx.fillStyle = "#050505"
  ctx.fillRect(b.x - 2, b.y - 2, b.w + 4, b.h + 4)
  var lines = randi(0, 3)
  for (var k = 0; k < lines; k++) {
    ctx.globalAlpha = rand(0.25, 0.7)
    ctx.fillStyle = pick(palette)
    ctx.fillRect(rand(b.x, b.x + b.w), b.y - 2, rand(0.6, 2), b.h + 4)
  }
  ctx.globalAlpha = 0.5
  var g = ctx.createLinearGradient(b.x, b.y, b.x + b.w, b.y + b.h)
  g.addColorStop(0, "rgba(40,40,60,0.35)")
  g.addColorStop(1, "rgba(0,0,0,0)")
  ctx.fillStyle = g
  ctx.fillRect(b.x - 2, b.y - 2, b.w + 4, b.h + 4)
  ctx.restore()
  tracePoly(ctx, poly)
  ctx.strokeStyle = "rgba(200,220,255,0.35)"
  ctx.lineWidth = 1
  ctx.stroke()
}

function drawBulletHole(ctx, x, y, size, crack) {
  drawCrack(ctx, crack, 0.7)
  glow(ctx, x, y, 11 * size, "rgba(255,255,255,0.85)", "rgba(255,255,255,0)")
  var r = rand(2.6, 3.6) * size
  var g = ctx.createRadialGradient(x, y, 0, x, y, r * 1.8)
  g.addColorStop(0, "rgba(0,0,0,1)")
  g.addColorStop(0.55, "rgba(10,10,10,0.95)")
  g.addColorStop(1, "rgba(60,60,60,0)")
  ctx.fillStyle = g
  ctx.beginPath(); ctx.arc(x, y, r * 1.8, 0, Math.PI * 2); ctx.fill()
  ctx.strokeStyle = "rgba(255,255,255,0.55)"
  ctx.lineWidth = 0.8
  ctx.beginPath(); ctx.arc(x, y, r * 1.25, 0, Math.PI * 2); ctx.stroke()
}

function drawScorch(ctx, x, y, r, alpha) {
  var g = ctx.createRadialGradient(x, y, 0, x, y, r)
  g.addColorStop(0, "rgba(10,6,2," + alpha + ")")
  g.addColorStop(0.5, "rgba(20,10,4," + (alpha * 0.6) + ")")
  g.addColorStop(1, "rgba(30,15,5,0)")
  ctx.fillStyle = g
  ctx.fillRect(x - r, y - r, r * 2, r * 2)
}

function drawLaserCut(ctx, x1, y1, x2, y2) {
  ctx.lineCap = "round"
  ctx.strokeStyle = "rgba(255,110,20,0.18)"
  ctx.lineWidth = 9
  ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke()
  ctx.strokeStyle = "rgba(12,4,0,0.95)"
  ctx.lineWidth = 2.6
  ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke()
}

// ---------------------------------------------------------------------------
// Tool sprites (cursor + toolbar icons)
// ---------------------------------------------------------------------------

function outline(ctx) {
  ctx.lineWidth = 1.5
  ctx.strokeStyle = "rgba(0,0,0,0.75)"
  ctx.stroke()
}

// Hotspot at (x, y) is the striking face; `ang` lifts the head around the
// end of the handle, so 0 means the head is on target.
function drawHammer(ctx, x, y, ang, accent, s) {
  s = s || 1
  ctx.save()
  ctx.translate(x, y); ctx.scale(s, s)
  ctx.translate(80, 0); ctx.rotate(ang); ctx.translate(-80, 0)
  ctx.beginPath(); ctx.rect(16, -4.5, 66, 9)
  var wood = ctx.createLinearGradient(0, -5, 0, 5)
  wood.addColorStop(0, "#c08a4a"); wood.addColorStop(1, "#7a4f22")
  ctx.fillStyle = wood; ctx.fill(); outline(ctx)
  ctx.beginPath(); ctx.rect(0, -16, 22, 32)
  var steel = ctx.createLinearGradient(0, -16, 0, 16)
  steel.addColorStop(0, "#e8e8ea"); steel.addColorStop(0.5, "#9a9ca2"); steel.addColorStop(1, "#5d5f66")
  ctx.fillStyle = steel; ctx.fill(); outline(ctx)
  ctx.fillStyle = accent; ctx.fillRect(22, -16, 3, 32)
  ctx.restore()
}

function drawCrosshair(ctx, x, y, r, accent) {
  var styles = [["rgba(0,0,0,0.7)", 3.5], [accent, 1.6]]
  for (var i = 0; i < styles.length; i++) {
    ctx.strokeStyle = styles[i][0]; ctx.lineWidth = styles[i][1]
    ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.stroke()
    ctx.beginPath()
    ctx.moveTo(x - r - 7, y); ctx.lineTo(x - r + 5, y)
    ctx.moveTo(x + r - 5, y); ctx.lineTo(x + r + 7, y)
    ctx.moveTo(x, y - r - 7); ctx.lineTo(x, y - r + 5)
    ctx.moveTo(x, y + r - 5); ctx.lineTo(x, y + r + 7)
    ctx.stroke()
  }
  ctx.fillStyle = accent
  ctx.fillRect(x - 1, y - 1, 2, 2)
}

function drawGun(ctx, x, y, smg, accent) {
  ctx.save(); ctx.translate(x, y)
  ctx.fillStyle = "#3a3c42"
  ctx.beginPath()
  if (smg) {
    ctx.rect(-18, -8, 34, 10); ctx.rect(-6, 2, 7, 14); ctx.rect(6, 2, 5, 9); ctx.rect(16, -5, 5, 3)
  } else {
    ctx.rect(-16, -9, 30, 9)
    ctx.moveTo(4, 0); ctx.lineTo(13, 0); ctx.lineTo(16, 15); ctx.lineTo(7, 15); ctx.closePath()
  }
  ctx.fill(); outline(ctx)
  ctx.fillStyle = accent
  ctx.fillRect(smg ? -18 : -16, smg ? -8 : -9, 3, 3)
  ctx.restore()
}

function drawNozzle(ctx, x, y, accent, s) {
  s = s || 1
  ctx.save(); ctx.translate(x, y); ctx.scale(s, s)
  ctx.beginPath(); ctx.rect(-4, 4, 8, 14)
  ctx.fillStyle = "#6e7077"; ctx.fill(); outline(ctx)
  ctx.beginPath(); ctx.rect(-8, 18, 16, 26)
  ctx.fillStyle = "#b8352b"; ctx.fill(); outline(ctx)
  ctx.fillStyle = accent; ctx.fillRect(-8, 24, 16, 3)
  // pilot light
  ctx.save(); ctx.translate(0, 1); ctx.scale(1, 1.7)
  ctx.fillStyle = "rgba(90,160,255,0.9)"
  ctx.beginPath(); ctx.arc(0, 0, 2.5, 0, Math.PI * 2); ctx.fill()
  ctx.restore()
  ctx.restore()
}

function drawLaserPointer(ctx, x, y, firing, accent) {
  glow(ctx, x, y, firing ? 30 : 13, firing ? "rgba(255,230,200,1)" : "rgba(255,120,80,0.6)", "rgba(255,80,0,0)")
  ctx.fillStyle = "#ff2a1a"
  ctx.beginPath(); ctx.arc(x, y, 3, 0, Math.PI * 2); ctx.fill()
  ctx.strokeStyle = accent; ctx.lineWidth = 1.5
  ctx.beginPath(); ctx.arc(x, y, 10, 0, Math.PI * 2); ctx.stroke()
}

function drawBomb(ctx, x, y, s, lit) {
  ctx.save(); ctx.translate(x, y); ctx.scale(s, s)
  ctx.beginPath(); ctx.arc(0, 0, 15, 0, Math.PI * 2)
  var g = ctx.createRadialGradient(-5, -6, 1, 0, 0, 16)
  g.addColorStop(0, "#6a6c74"); g.addColorStop(1, "#141418")
  ctx.fillStyle = g; ctx.fill(); outline(ctx)
  ctx.fillStyle = "#3a3c42"; ctx.fillRect(-5, -19, 10, 6)
  ctx.strokeStyle = "#c9a36a"; ctx.lineWidth = 2
  ctx.beginPath(); ctx.moveTo(0, -19); ctx.quadraticCurveTo(6, -27, 12, -24); ctx.stroke()
  if (lit) glow(ctx, 12, -24, 11, "rgba(255,240,200,1)", "rgba(255,120,0,0)")
  ctx.restore()
}

function drawDrop(ctx, x, y, s, accent) {
  ctx.save(); ctx.translate(x, y); ctx.scale(s, s)
  ctx.beginPath()
  ctx.moveTo(0, -2)
  ctx.bezierCurveTo(4, 6, 10, 10, 10, 16)
  ctx.arc(0, 16, 10, 0, Math.PI, false)
  ctx.bezierCurveTo(-10, 10, -4, 6, 0, -2)
  ctx.fillStyle = accent; ctx.fill(); outline(ctx)
  ctx.fillStyle = "rgba(255,255,255,0.55)"
  ctx.beginPath(); ctx.arc(-4, 15, 2.2, 0, Math.PI * 2); ctx.fill()
  ctx.restore()
}

// Cursor for a tool, drawn centred in a canvas of size `size` (the pointer
// hotspot is the canvas centre). `state` carries swing/recoil animation.
function drawCursor(ctx, tool, size, state, accent) {
  var c = size / 2
  switch (tool) {
  case "hammer": drawHammer(ctx, c, c, 0.55 * (1 - state.swing * state.swing), accent); break
  case "pistol": drawCrosshair(ctx, c, c - state.recoil * 6, 13, accent); break
  case "smg": drawCrosshair(ctx, c + rand(-1, 1) * state.recoil * 3, c - state.recoil * 4, 22, accent); break
  case "flame": drawNozzle(ctx, c, c, accent); break
  case "laser": drawLaserPointer(ctx, c, c, state.firing, accent); break
  case "bomb": drawBomb(ctx, c, c, 1, false); break
  case "melt": drawDrop(ctx, c, c, 1, accent); break
  }
}

// Toolbar icon, drawn into a 44x44 logical box.
function drawIcon(ctx, tool, accent) {
  switch (tool) {
  case "hammer": drawHammer(ctx, 8, 26, 0.3, accent, 0.42); break
  case "pistol": drawGun(ctx, 22, 22, false, accent); break
  case "smg": drawGun(ctx, 22, 22, true, accent); break
  case "flame": drawNozzle(ctx, 20, 2, accent, 0.85); break
  case "laser":
    ctx.lineCap = "round"
    ctx.strokeStyle = "#ff3a1a"; ctx.lineWidth = 3
    ctx.beginPath(); ctx.moveTo(6, 36); ctx.lineTo(36, 8); ctx.stroke()
    ctx.strokeStyle = "#ffd0a0"; ctx.lineWidth = 1
    ctx.beginPath(); ctx.moveTo(6, 36); ctx.lineTo(36, 8); ctx.stroke()
    glow(ctx, 36, 8, 11, "rgba(255,255,255,1)", "rgba(255,120,0,0)")
    break
  case "bomb": drawBomb(ctx, 20, 25, 0.9, false); break
  case "melt": drawDrop(ctx, 22, 6, 1.3, accent); break
  }
}
