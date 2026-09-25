import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Particles
import qs.Commons
import "Game.js" as Game

// Screen Breaker: screenshot the focused monitor, then smash it.
//
// Summon with `omarchy-shell shell summon <id> '{}'`. open() waits a moment
// so whatever summoned us (the Omarchy menu, a keybinding) is gone, grabs
// the monitor with grim, and shows the overlay once the image is loaded.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  readonly property string pluginId: (manifest && manifest.id) || "io.github.justwiebe.screen-breaker"
  readonly property string assetDir: Qt.resolvedUrl("assets").toString().replace(/^file:\/\//, "")
  readonly property string shotPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/screen-breaker.png"

  property bool capturing: false
  property string monitorName: ""
  property int shotSerial: 0
  property string shotUrl: ""

  // Theme
  readonly property string accentCss: String(Color.accent)
  readonly property var deadPixelPalette: [accentCss, String(Color.urgent), String(Color.foreground),
    "#ff3b3b", "#3bff6b", "#3b8bff", "#ffffff"]
  readonly property color panelBackground: Color.popups.background
  readonly property color panelBorder: Color.popups.border
  readonly property color panelText: Color.popups.text
  readonly property string fontFamily: Style.font.menuFamily

  readonly property var tools: [
    { id: "hammer", name: "Hammer", desc: "Hit the same spot again to knock glass out" },
    { id: "pistol", name: "Pistol", desc: "Click to fire" },
    { id: "smg", name: "SMG", desc: "Hold to spray" },
    { id: "flame", name: "Flamethrower", desc: "Hold to burn — fires keep burning" },
    { id: "laser", name: "Laser", desc: "Hold and drag to cut" },
    { id: "bomb", name: "Bomb", desc: "Click to drop — stand back" },
    { id: "melt", name: "sudo rm -rf", desc: "Hold to melt the pixels" }
  ]
  property int toolIndex: 0
  readonly property var tool: tools[toolIndex]

  readonly property var tiers: [
    [0, "Pristine"], [60, "Scuffed"], [600, "Cracked"], [2500, "Warranty void"],
    [8000, "Totaled"], [20000, "Beyond the Arch Wiki"], [50000, "Please touch grass"]
  ]
  property real cost: 0
  readonly property string tier: {
    var name = tiers[0][1]
    for (var i = 0; i < tiers.length; i++) if (cost >= tiers[i][0]) name = tiers[i][1]
    return name
  }

  // Input + per-frame state
  property real pointerX: 0
  property real pointerY: 0
  property real lastX: 0
  property real lastY: 0
  property bool pointerDown: false
  property bool pointerInside: false
  readonly property bool overHud: toolbarHover.hovered || meterHover.hovered || keysHover.hovered
  readonly property bool firing: pointerDown && !overHud
  property var cursorState: ({ swing: 0, recoil: 0, firing: false })
  property real smgCooldown: 0
  property real burnCooldown: 0
  property real shakeMag: 0
  property real shakeTime: 0
  property bool hudVisible: true

  property var hits: []
  property var shards: []
  property var drips: []
  property var burns: []
  property var bombs: []

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  function open(payloadJson) {
    if (opened || capturing) return
    var monitor = Hyprland.focusedMonitor
    monitorName = monitor ? monitor.name : ""
    capturing = true
    captureDelay.restart()
  }

  function close() {
    opened = false
    capturing = false
    captureDelay.stop()
    sound.stopAll()
    resetDamage()
  }

  function dismiss() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }

  function start() {
    resetDamage()
    cost = 0
    toolIndex = 0
    pointerDown = false
    hudVisible = true
    intro.opacity = 1
    introTimer.restart()
    opened = true
    Qt.callLater(function() { keys.forceActiveFocus() })
  }

  function resetDamage() {
    damage.clear()
    destroyAll(shards)
    destroyAll(drips)
    destroyAll(burns)
    destroyAll(bombs)
    shards = []; drips = []; burns = []; bombs = []; hits = []
    particles.reset()
    shakeTime = 0
    scene.x = 0; scene.y = 0
  }

  function destroyAll(list) {
    for (var i = 0; i < list.length; i++) {
      var item = list[i].item || list[i]
      if (item && item.destroy) item.destroy()
    }
  }

  Timer {
    id: captureDelay
    interval: 250
    onTriggered: {
      grim.command = root.monitorName ? ["grim", "-o", root.monitorName, root.shotPath] : ["grim", root.shotPath]
      grim.running = true
    }
  }

  Process {
    id: grim
    onExited: function(exitCode) {
      if (!root.capturing) return
      if (exitCode !== 0) {
        root.capturing = false
        Quickshell.execDetached(["notify-send", "-a", "Screen Breaker", "Couldn't take a screenshot", "grim exited with " + exitCode])
        root.dismiss()
        return
      }
      root.shotSerial++
      root.shotUrl = "file://" + root.shotPath + "?" + root.shotSerial
    }
  }

  // ---------------------------------------------------------------------------
  // Tools
  // ---------------------------------------------------------------------------

  function selectTool(i) {
    toolIndex = (i + tools.length) % tools.length
    sound.stopAll()
    cursor.requestPaint()
  }

  function toolDown(x, y) {
    intro.opacity = 0
    switch (tool.id) {
    case "hammer": hammer(x, y); break
    case "pistol": fire(x, y, false); break
    case "smg": smgCooldown = 0; break
    case "bomb": dropBomb(x, y); break
    }
  }

  function hammer(x, y) {
    cursorState.swing = 1
    var near = 0
    for (var i = 0; i < hits.length; i++)
      if (Math.hypot(hits[i][0] - x, hits[i][1] - y) < 70) near++
    var crack = Game.makeCrack(x, y, { rays: Game.randi(9, 14), len: Game.rand(110, 200), rings: 4 })
    damage.paint(Game.crackBounds(crack), function(ctx) { Game.drawCrack(ctx, crack, 1) })
    var fell = 0
    if (near >= 1) {
      var chance = near >= 2 ? 0.85 : 0.5
      fell = shatter(crack, near >= 2 ? 2 : 1, function(j) { return chance - j * 0.2 }, 1)
    }
    hits.push([x, y])
    if (hits.length > 200) hits.shift()
    glassBurst.burst(10, x, y)
    sound.play("crack-" + Game.randi(1, 3))
    if (fell) sound.play("shatter", 0.8)
    shake(near >= 2 ? 9 : 5, 0.15)
    cost += Game.rand(40, 90) + fell * 15
  }

  function fire(x, y, light) {
    var size = light ? 0.85 : 1
    var crack = Game.makeCrack(x, y, { rays: Game.randi(5, 9), len: Game.rand(18, 45) * size, rings: 1, ringChance: 0.4, jag: 0.35 })
    damage.paint(Game.crackBounds(crack), function(ctx) { Game.drawBulletHole(ctx, x, y, size, crack) })
    flashBurst.burst(1, x, y)
    glassBurst.burst(6, x, y)
    sparkBurst.burst(4, x, y)
    casingBurst.burst(1, x + 30, y + 10)
    cursorState.recoil = 1
    if (!light) {
      sound.play("gunshot")
      sound.play("casing", 0.6)
    }
    shake(light ? 2.5 : 5, 0.08)
    cost += light ? Game.rand(15, 30) : Game.rand(30, 60)
  }

  // Knock out the cells of a crack; `chance(ring)` is the odds per cell.
  function shatter(crack, maxRing, chance, force) {
    var n = 0
    for (var j = 0; j <= maxRing; j++) {
      for (var i = 0; i < crack.rays.length; i++) {
        if (Math.random() > chance(j)) continue
        var poly = Game.cellPolygon(crack, i, j)
        if (!poly) continue
        spawnShard(poly, crack.cx, crack.cy, force)
        n++
      }
    }
    return n
  }

  function spawnShard(poly, cx, cy, force) {
    var b = Game.bbox(poly)
    if (b.w < 2 || b.h < 2) return
    var palette = deadPixelPalette
    damage.paint(b, function(ctx) { Game.drawDeadPixels(ctx, poly, palette) })

    var mx = b.x + b.w / 2, my = b.y + b.h / 2
    var dx = mx - cx, dy = my - cy, dist = Math.hypot(dx, dy) || 1
    var shard = shardComponent.createObject(shardLayer, {
      poly: poly, texture: shot, cx: mx, cy: my,
      spin: Game.rand(-240, 240) * force,
      vx: (dx / dist) * Game.rand(20, 120) * force,
      vy: (dy / dist) * Game.rand(10, 80) * force - Game.rand(0, 60) * force,
      delay: Game.rand(0, 0.15)
    })
    if (!shard) return
    shards.push(shard)
    if (shards.length > 250) shards.shift().destroy()
  }

  function dropBomb(x, y) {
    var item = bombComponent.createObject(scene, { x: x - 30, y: y - 30 })
    bombs.push({ item: item, x: x, y: y, t: 0, fuse: 1.4, nextTick: 0 })
  }

  function explode(b) {
    var x = b.x, y = b.y
    damage.paint(Game.circleBounds(x, y, 190), function(ctx) {
      Game.drawScorch(ctx, x, y, 190, 0.55)
      Game.drawScorch(ctx, x, y, 100, 0.85)
    })
    var crack = Game.makeCrack(x, y, { rays: Game.randi(16, 22), len: Game.rand(260, 380), rings: 5, ringChance: 0.7 })
    damage.paint(Game.crackBounds(crack), function(ctx) { Game.drawCrack(ctx, crack, 1.2) })
    var odds = [1, 0.9, 0.55, 0.25]
    shatter(crack, 3, function(j) { return odds[j] }, 3.2)
    damage.paint(Game.circleBounds(x, y, 45), function(ctx) { Game.drawScorch(ctx, x, y, 45, 0.9) })

    fireBurst.burst(60, x, y)
    bigSparkBurst.burst(50, x, y)
    bigGlassBurst.burst(40, x, y)
    smokeBurst.burst(25, x, y)
    for (var k = 0; k < 8; k++) spawnBurn(x + Game.rand(-90, 90), y + Game.rand(-90, 90))
    flash.color = "#ffd296"
    flash.opacity = 0.85
    flashFade.restart()
    shake(24, 0.7)
    sound.play("boom")
    cost += Game.rand(1200, 1800)
  }

  function spawnBurn(x, y) {
    if (burns.length >= 60) return
    var item = burnComponent.createObject(scene, { x: x, y: y })
    if (item) burns.push({ item: item, x: x, y: y, life: 0, max: Game.rand(2.5, 5) })
  }

  function spawnDrip() {
    if (drips.length >= 900) drips.shift().destroy()
    var w = Game.rand(2, 9)
    var x = Math.round(pointerX + Game.rand(-45, 45))
    var drip = dripComponent.createObject(dripLayer, {
      source: shotUrl, x: x, width: w,
      startY: pointerY + Game.rand(-25, 25), length: Game.rand(25, 90),
      speed: Game.rand(40, 190), life: Game.rand(1, 3.2)
    })
    if (drip) drips.push(drip)
  }

  function shake(mag, dur) {
    shakeMag = Math.max(shakeMag, mag)
    shakeTime = Math.max(shakeTime, dur)
  }

  // ---------------------------------------------------------------------------
  // Frame loop
  // ---------------------------------------------------------------------------

  function tick(dt) {
    var x = pointerX, y = pointerY
    var id = tool.id
    var holding = firing && pointerInside

    // held tools
    sound.setLoop("smg", holding && id === "smg")
    sound.setLoop("flame", holding && id === "flame")
    sound.setLoop("laser", holding && id === "laser")
    sound.setLoop("melt", holding && id === "melt")

    if (holding && id === "smg") {
      smgCooldown -= dt
      while (smgCooldown <= 0) {
        smgCooldown += 0.075
        fire(x + Game.rand(-22, 22), y + Game.rand(-22, 22), true)
      }
    }
    if (holding && id === "flame") {
      damage.paint(Game.circleBounds(x, y - 15, 60), function(ctx) {
        for (var k = 0; k < 3; k++) Game.drawScorch(ctx, x + Game.rand(-26, 26), y + Game.rand(-40, 10), Game.rand(12, 30), 0.05)
      })
      burnCooldown -= dt
      if (burnCooldown <= 0) {
        burnCooldown = 0.12
        spawnBurn(x + Game.rand(-20, 20), y + Game.rand(-20, 20))
      }
      cost += dt * 90
    }
    if (holding && id === "laser") {
      var x0 = lastX, y0 = lastY
      damage.paint({ x: Math.min(x0, x) - 10, y: Math.min(y0, y) - 10, w: Math.abs(x - x0) + 20, h: Math.abs(y - y0) + 20 }, function(ctx) {
        Game.drawLaserCut(ctx, x0, y0, x, y)
        Game.drawScorch(ctx, x, y, 5, 0.25)
      })
      var steps = Math.max(1, Math.ceil(Math.hypot(x - x0, y - y0) / 4))
      for (var s = 1; s <= steps; s++) emberBurst.burst(1, x0 + (x - x0) * s / steps, y0 + (y - y0) * s / steps)
      sparkBurst.burst(3, x, y)
      cost += Math.hypot(x - x0, y - y0) * 0.35 + dt * 10
    }
    if (holding && id === "melt") {
      for (var d = 0; d < 4; d++) spawnDrip()
      cost += dt * 120
    }
    lastX = x; lastY = y

    // lingering fires
    for (var i = burns.length - 1; i >= 0; i--) {
      var burn = burns[i]
      burn.life += dt
      if (burn.life > burn.max) { burn.item.destroy(); burns.splice(i, 1); continue }
      burn.item.emitRate = 30 * (1 - burn.life / burn.max) + 5
      if (Math.random() < 0.3) {
        let bx = burn.x + Game.rand(-8, 8), by = burn.y + Game.rand(-12, 4)
        damage.paint(Game.circleBounds(bx, by, 16), function(ctx) { Game.drawScorch(ctx, bx, by, Game.rand(7, 15), 0.04) })
      }
    }

    // melting
    for (var m = 0; m < drips.length; m++) drips[m].step(dt)

    // bombs
    for (var n = bombs.length - 1; n >= 0; n--) {
      var bomb = bombs[n]
      bomb.t += dt
      bomb.nextTick -= dt
      if (bomb.nextTick <= 0) {
        sound.play("tick")
        bomb.nextTick = Math.max(0.06, 0.3 * (1 - bomb.t / bomb.fuse))
      }
      fuseBurst.burst(1, bomb.x + 13, bomb.y - 26)
      bomb.item.scale = 1.1 + Math.sin(bomb.t * 30) * 0.04
      if (bomb.t >= bomb.fuse) {
        bomb.item.destroy()
        bombs.splice(n, 1)
        explode(bomb)
      }
    }
    sound.setLoop("fuse", bombs.length > 0)

    // shards
    for (var k = shards.length - 1; k >= 0; k--) {
      if (!shards[k].step(dt, scene.height)) { shards[k].destroy(); shards.splice(k, 1) }
    }

    // screen shake
    if (shakeTime > 0) {
      shakeTime -= dt
      var mag = shakeMag * (Math.max(0, shakeTime) / 0.7 + 0.3)
      scene.x = Game.rand(-mag, mag)
      scene.y = Game.rand(-mag, mag)
    } else if (scene.x || scene.y) {
      scene.x = 0; scene.y = 0; shakeMag = 0
    }

    // cursor animation
    var st = cursorState
    var animating = st.swing > 0 || st.recoil > 0 || id === "smg" || st.firing !== holding
    st.swing = Math.max(0, st.swing - dt * 7)
    st.recoil = Math.max(0, st.recoil - dt * (id === "smg" ? 12 : 8))
    st.firing = holding
    if (animating) cursor.requestPaint()
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  function repair() {
    resetDamage()
    cost = 0
    flash.color = "white"
    flash.opacity = 0.5
    flashFade.restart()
    sound.play("repair")
    toast("Screen repaired. Please break responsibly.")
  }

  function save() {
    var dir = Quickshell.env("OMARCHY_SCREENSHOT_DIR") || Quickshell.env("XDG_PICTURES_DIR") || (Quickshell.env("HOME") + "/Pictures")
    var name = "/screen-breaker-" + Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss") + ".png"
    // grabToImage already renders at the display's device pixel ratio.
    scene.grabToImage(function(result) {
      // Fall back to $HOME when the pictures directory doesn't exist.
      var path = dir + name
      if (!result.saveToFile(path)) {
        path = Quickshell.env("HOME") + name
        if (!result.saveToFile(path)) {
          toast("Couldn't save the wreckage")
          return
        }
      }
      toast("Saved to " + path.replace(Quickshell.env("HOME"), "~"))
      Quickshell.execDetached(["notify-send", "-a", "Screen Breaker", "Wreckage saved", path])
    })
  }

  function toast(message) {
    toastText.text = message
    toastBox.shown = true
    toastTimer.restart()
  }

  // ---------------------------------------------------------------------------
  // Components
  // ---------------------------------------------------------------------------

  Sound { id: sound; dir: root.assetDir + "/sounds" }

  Component { id: shardComponent; Shard {} }
  Component { id: dripComponent; Drip {} }

  Component {
    id: bombComponent
    Canvas {
      width: 60; height: 60
      onPaint: Game.drawBomb(getContext("2d"), 30, 30, 1, true)
    }
  }

  Component {
    id: burnComponent
    Emitter {
      system: particles
      group: "fire"
      width: 12; height: 4
      emitRate: 30
      lifeSpan: 500; lifeSpanVariation: 200
      size: 18; sizeVariation: 8; endSize: 36
      velocity: AngleDirection { angle: 270; angleVariation: 15; magnitude: 60; magnitudeVariation: 30 }
      acceleration: PointDirection { y: -60 }
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    screen: {
      var screens = Quickshell.screens
      for (var i = 0; i < screens.length; i++) if (screens[i].name === root.monitorName) return screens[i]
      return null
    }
    anchors { top: true; bottom: true; left: true; right: true }
    color: "black"
    WlrLayershell.namespace: "omarchy-screen-breaker"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    FrameAnimation {
      running: root.opened
      onTriggered: root.tick(Math.min(0.05, frameTime))
    }

    // Everything that gets shaken, saved, and destroyed.
    Item {
      id: scene
      width: parent.width
      height: parent.height

      Image {
        id: shot
        anchors.fill: parent
        source: root.shotUrl
        cache: true
        smooth: false
        onStatusChanged: {
          if (!root.capturing) return
          if (status === Image.Ready) {
            root.capturing = false
            root.start()
          } else if (status === Image.Error) {
            root.capturing = false
            root.dismiss()
          }
        }
      }

      Item { id: dripLayer; anchors.fill: parent }
      DamageLayer { id: damage; anchors.fill: parent }
      Item { id: shardLayer; anchors.fill: parent }

      ParticleSystem { id: particles; anchors.fill: parent }

      // Smoke first so fire draws over it
      ImageParticle {
        system: particles; groups: ["smoke"]
        source: "assets/particles/smoke.png"
        entryEffect: ImageParticle.Fade
      }
      ImageParticle {
        system: particles; groups: ["fire"]
        source: "assets/particles/fire.png"
        entryEffect: ImageParticle.Fade
      }
      ImageParticle {
        system: particles; groups: ["spark"]
        source: "assets/particles/spark.png"
        autoRotation: true
        entryEffect: ImageParticle.Fade
      }
      ImageParticle {
        system: particles; groups: ["glass"]
        source: "assets/particles/glass.png"
        rotationVariation: 180
        rotationVelocityVariation: 360
        entryEffect: ImageParticle.Fade
      }
      ImageParticle {
        system: particles; groups: ["casing"]
        source: "assets/particles/casing.png"
        rotationVelocity: 540
        rotationVelocityVariation: 360
      }
      ImageParticle {
        system: particles; groups: ["flash"]
        source: "assets/particles/glow.png"
        entryEffect: ImageParticle.None
      }
      ImageParticle {
        system: particles; groups: ["ember"]
        source: "assets/particles/glow.png"
        color: "#ff8a30"
        entryEffect: ImageParticle.Fade
      }

      Gravity { system: particles; groups: ["spark", "glass", "casing"]; angle: 90; magnitude: 1100 }

      // Held flamethrower
      Emitter {
        system: particles; group: "fire"
        x: root.pointerX - 4; y: root.pointerY - 4; width: 8; height: 8
        enabled: root.firing && root.tool.id === "flame"
        emitRate: 260
        lifeSpan: 550; lifeSpanVariation: 200
        size: 34; sizeVariation: 12; endSize: 72
        velocity: AngleDirection { angle: 270; angleVariation: 30; magnitude: 260; magnitudeVariation: 120 }
        acceleration: PointDirection { y: -120 }
      }
      Emitter {
        system: particles; group: "smoke"
        x: root.pointerX; y: root.pointerY - 40
        enabled: root.firing && root.tool.id === "flame"
        emitRate: 12
        lifeSpan: 1500; lifeSpanVariation: 500
        size: 30; endSize: 110
        velocity: AngleDirection { angle: 270; angleVariation: 25; magnitude: 60; magnitudeVariation: 30 }
      }

      // One-shot bursts, fired with burst(count, x, y)
      Emitter {
        id: fireBurst; system: particles; group: "fire"; enabled: false
        lifeSpan: 750; lifeSpanVariation: 350
        size: 70; sizeVariation: 35; endSize: 130
        velocity: AngleDirection { angleVariation: 180; magnitude: 380; magnitudeVariation: 320 }
        acceleration: PointDirection { y: -80 }
      }
      Emitter {
        id: smokeBurst; system: particles; group: "smoke"; enabled: false
        lifeSpan: 2300; lifeSpanVariation: 700
        size: 90; sizeVariation: 30; endSize: 220
        velocity: AngleDirection { angleVariation: 180; magnitude: 70; magnitudeVariation: 50 }
        acceleration: PointDirection { y: -30 }
      }
      Emitter {
        id: sparkBurst; system: particles; group: "spark"; enabled: false
        lifeSpan: 350; lifeSpanVariation: 200
        size: 14; sizeVariation: 4
        velocity: AngleDirection { angleVariation: 180; magnitude: 330; magnitudeVariation: 200 }
      }
      Emitter {
        id: bigSparkBurst; system: particles; group: "spark"; enabled: false
        lifeSpan: 900; lifeSpanVariation: 400
        size: 18; sizeVariation: 6
        velocity: AngleDirection { angleVariation: 180; magnitude: 750; magnitudeVariation: 400 }
      }
      Emitter {
        id: fuseBurst; system: particles; group: "spark"; enabled: false
        lifeSpan: 300; size: 8
        velocity: AngleDirection { angle: 270; angleVariation: 70; magnitude: 90; magnitudeVariation: 50 }
      }
      Emitter {
        id: glassBurst; system: particles; group: "glass"; enabled: false
        lifeSpan: 900; lifeSpanVariation: 300
        size: 7; sizeVariation: 3
        velocity: AngleDirection { angleVariation: 180; magnitude: 200; magnitudeVariation: 120 }
      }
      Emitter {
        id: bigGlassBurst; system: particles; group: "glass"; enabled: false
        lifeSpan: 1400; lifeSpanVariation: 400
        size: 9; sizeVariation: 5
        velocity: AngleDirection { angleVariation: 180; magnitude: 550; magnitudeVariation: 350 }
      }
      Emitter {
        id: casingBurst; system: particles; group: "casing"; enabled: false
        lifeSpan: 1800; size: 10
        velocity: AngleDirection { angle: 300; angleVariation: 20; magnitude: 350; magnitudeVariation: 80 }
      }
      Emitter {
        id: flashBurst; system: particles; group: "flash"; enabled: false
        lifeSpan: 70; size: 80
      }
      Emitter {
        id: emberBurst; system: particles; group: "ember"; enabled: false
        lifeSpan: 1300; lifeSpanVariation: 200
        size: 9; endSize: 3
      }
    }

    Rectangle {
      id: flash
      anchors.fill: parent
      opacity: 0
      color: "white"
      NumberAnimation on opacity { id: flashFade; running: false; to: 0; duration: 350; easing.type: Easing.OutQuad }
    }

    // Input: the whole screen is the canvas. HUD panels sit above this.
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      hoverEnabled: true
      cursorShape: Qt.BlankCursor

      onEntered: root.pointerInside = true
      onExited: root.pointerInside = false
      onPositionChanged: function(mouse) {
        root.pointerX = mouse.x
        root.pointerY = mouse.y
        root.pointerInside = true
      }
      onPressed: function(mouse) {
        root.pointerX = mouse.x
        root.pointerY = mouse.y
        if (mouse.button === Qt.RightButton) {
          root.selectTool(root.toolIndex + 1)
          return
        }
        root.lastX = mouse.x
        root.lastY = mouse.y
        root.pointerDown = true
        root.toolDown(mouse.x, mouse.y)
      }
      onReleased: function(mouse) { if (mouse.button === Qt.LeftButton) root.pointerDown = false }
      onCanceled: root.pointerDown = false
      onWheel: function(wheel) { root.selectTool(root.toolIndex + (wheel.angleDelta.y < 0 ? 1 : -1)) }
    }

    // Keyboard
    Item {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.onPressed: function(event) {
        var k = event.key
        if (k >= Qt.Key_1 && k < Qt.Key_1 + root.tools.length) { root.selectTool(k - Qt.Key_1); intro.opacity = 0 }
        else if (k === Qt.Key_Escape || k === Qt.Key_Q) root.dismiss()
        else if (k === Qt.Key_R) root.repair()
        else if (k === Qt.Key_S) root.save()
        else if (k === Qt.Key_H) root.hudVisible = !root.hudVisible
        else if (k === Qt.Key_M) root.toast(sound.toggleMute() ? "Muted" : "Sound on")
        else if (k === Qt.Key_Tab) root.selectTool(root.toolIndex + 1)
        else if (k === Qt.Key_Backtab) root.selectTool(root.toolIndex - 1)
        else return
        event.accepted = true
      }
    }

    // Tool cursor (the system cursor is hidden over the game)
    Canvas {
      id: cursor
      width: 200; height: 200
      x: root.pointerX - 100
      y: root.pointerY - 100
      visible: root.pointerInside && !root.overHud
      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        ctx.clearRect(0, 0, width, height)
        Game.drawCursor(ctx, root.tool.id, width, root.cursorState, root.accentCss)
      }
    }

    // ---------------------------------------------------------------------------
    // HUD
    // ---------------------------------------------------------------------------

    component HudPanel: Rectangle {
      color: root.panelBackground
      border.color: root.panelBorder
      border.width: Math.max(1, Style.space(2))
      radius: Style.cornerRadius
    }

    component HudText: Text {
      color: root.panelText
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      textFormat: Text.PlainText
    }

    Item {
      id: hud
      anchors.fill: parent
      opacity: root.hudVisible ? 1 : 0
      visible: opacity > 0
      Behavior on opacity { NumberAnimation { duration: 200 } }

      HudPanel {
        id: keysPanel
        x: Style.spacing.huge; y: Style.spacing.huge
        width: keysColumn.implicitWidth + Style.spacing.xxl * 2
        height: keysColumn.implicitHeight + Style.spacing.lg * 2
        HoverHandler { id: keysHover }
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
        Column {
          id: keysColumn
          anchors.centerIn: parent
          spacing: Style.spacing.xs
          HudText { text: "LMB use tool  ·  RMB / wheel / Tab switch  ·  1–7 pick"; opacity: 0.75 }
          HudText { text: "R repair  ·  S save  ·  M mute  ·  H hide HUD  ·  Esc quit"; opacity: 0.75 }
        }
      }

      HudPanel {
        id: meter
        anchors.right: parent.right; anchors.rightMargin: Style.spacing.huge
        y: Style.spacing.huge
        width: Math.max(Style.space(220), meterColumn.implicitWidth + Style.spacing.xxl * 2)
        height: meterColumn.implicitHeight + Style.spacing.lg * 2
        HoverHandler { id: meterHover }
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
        Column {
          id: meterColumn
          anchors.right: parent.right; anchors.rightMargin: Style.spacing.xxl
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.xxs
          HudText {
            anchors.right: parent.right
            text: "ESTIMATED REPAIR"
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1.5
            opacity: 0.6
          }
          HudText {
            anchors.right: parent.right
            text: "$" + Math.round(root.cost).toLocaleString(Qt.locale("en_US"), "f", 0)
            color: Color.accent
            font.pixelSize: Style.font.displayLarge
            font.bold: true
          }
          HudText { anchors.right: parent.right; text: root.tier }
        }
      }

      HudPanel {
        id: toolLabel
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: toolbar.top; anchors.bottomMargin: Style.spacing.md
        width: toolLabelText.implicitWidth + Style.spacing.xxl * 2
        height: toolLabelText.implicitHeight + Style.spacing.sm * 2
        HudText {
          id: toolLabelText
          anchors.centerIn: parent
          textFormat: Text.StyledText
          text: "<b><font color='" + root.accentCss + "'>" + root.tool.name + "</font></b>  ·  " + root.tool.desc
        }
      }

      HudPanel {
        id: toolbar
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: Style.spacing.huge
        width: toolRow.implicitWidth + Style.spacing.md * 2
        height: toolRow.implicitHeight + Style.spacing.md * 2
        HoverHandler { id: toolbarHover }
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

        Row {
          id: toolRow
          anchors.centerIn: parent
          spacing: Style.spacing.sm

          Repeater {
            model: root.tools
            Rectangle {
              required property var modelData
              required property int index
              readonly property bool active: index === root.toolIndex
              width: 58; height: 58
              radius: Style.cornerRadius
              color: active ? Style.selectedAccentFill : (buttonArea.containsMouse ? Style.hoverFill : "transparent")
              border.color: active ? Color.accent : "transparent"
              border.width: Math.max(1, Style.space(2))

              Canvas {
                anchors.centerIn: parent
                width: 44; height: 44
                onPaint: Game.drawIcon(getContext("2d"), parent.modelData.id, root.accentCss)
              }
              HudText {
                x: 5; y: 2
                text: String(parent.index + 1)
                font.pixelSize: Style.font.caption
                color: parent.active ? Color.accent : root.panelText
                opacity: parent.active ? 1 : 0.6
              }
              MouseArea {
                id: buttonArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.selectTool(parent.index); intro.opacity = 0 }
              }
            }
          }
        }
      }
    }

    HudPanel {
      id: intro
      anchors.centerIn: parent
      width: introColumn.implicitWidth + Style.space(36) * 2
      height: introColumn.implicitHeight + Style.space(28) * 2
      visible: opacity > 0
      Behavior on opacity { NumberAnimation { duration: 400 } }

      Timer { id: introTimer; interval: 6000; onTriggered: intro.opacity = 0 }

      Column {
        id: introColumn
        anchors.centerIn: parent
        spacing: Style.spacing.md
        HudText {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "SCREEN BREAKER"
          color: Color.accent
          font.pixelSize: Style.font.displayLarge * 1.25
          font.bold: true
          font.letterSpacing: 3
        }
        HudText { anchors.horizontalCenter: parent.horizontalCenter; text: "for Omarchy"; opacity: 0.6 }
        Item { width: 1; height: Style.spacing.md }
        HudText { anchors.horizontalCenter: parent.horizontalCenter; text: "Your desktop is made of glass now."; font.pixelSize: Style.font.title }
        HudText { anchors.horizontalCenter: parent.horizontalCenter; text: "Pick a tool with 1–7 and click to break things."; font.pixelSize: Style.font.title }
        Item { width: 1; height: Style.spacing.sm }
        HudText {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "Nothing on your computer is harmed. Press Esc to go back to work."
          opacity: 0.6
        }
      }
    }

    HudPanel {
      id: toastBox
      property bool shown: false
      anchors.horizontalCenter: parent.horizontalCenter
      y: shown ? Style.spacing.huge : -height - 10
      width: toastText.implicitWidth + Style.spacing.xxl * 2
      height: toastText.implicitHeight + Style.spacing.lg * 2
      Behavior on y { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
      Timer { id: toastTimer; interval: 2600; onTriggered: toastBox.shown = false }
      HudText { id: toastText; anchors.centerIn: parent }
    }
  }
}
