-- ============================================================
--  BRICK BLITZ
--  A proper breakout-style game for TI-Nspire CX II
--  angle paddle physics / power-ups / combos / particles / shake
-- ============================================================

platform.apilevel = "2.5"

local W, H = 318, 212

local state = "title"   -- "title" | "playing" | "paused" | "gameover"
local BG = { 14, 14, 24 }

local function setColor(gc, c, g, b)
  if g ~= nil then gc:setColorRGB(c, g, b)
  else gc:setColorRGB(c[1], c[2], c[3]) end
end
local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi else return v end end
local function lerp(a, b, t) return a + (b - a) * t end
local function lerpColor(c, bg, t)
  return { math.floor(lerp(bg[1], c[1], t)), math.floor(lerp(bg[2], c[2], t)), math.floor(lerp(bg[3], c[3], t)) }
end

local hiScore = 0
local score = 0
local lives = 3
local level = 1
local combo = 0
local comboTimer = 0

local paddle = {}
local balls = {}
local bricks = {}
local powerups = {}
local particles = {}

local shakeTimer, shakeMag = 0, 0
local wideTimer, slowTimer = 0, 0

local ROWS, COLS = 6, 9
local ROW_COLORS = {
  {255,90,90}, {255,150,70}, {255,220,70}, {120,255,110}, {90,200,255}, {150,120,255}
}

-- ------------------------------------------------------------
-- persistence
-- ------------------------------------------------------------
local function loadHiScore()
  local ok, v = pcall(function() return var.recall("bb_hiscore") end)
  if ok and type(v) == "number" then hiScore = v else hiScore = 0 end
end

local function saveHiScore()
  if score > hiScore then
    hiScore = score
    pcall(function() var.store("bb_hiscore", hiScore) end)
  end
end

-- ------------------------------------------------------------
-- particles / shake helpers
-- ------------------------------------------------------------
local function spawnParticles(x, y, color, count)
  for i = 1, count do
    local ang = math.random() * math.pi * 2
    local spd = 1 + math.random() * 2.5
    table.insert(particles, {
      x = x, y = y, vx = math.cos(ang) * spd, vy = math.sin(ang) * spd,
      life = 20 + math.random(0, 10), maxLife = 30, color = color
    })
  end
end

local function shake(mag, dur)
  shakeMag = math.max(shakeMag, mag)
  shakeTimer = math.max(shakeTimer, dur)
end

local function updateParticles()
  for i = #particles, 1, -1 do
    local p = particles[i]
    p.x = p.x + p.vx
    p.y = p.y + p.vy
    p.vy = p.vy + 0.12
    p.life = p.life - 1
    if p.life <= 0 then table.remove(particles, i) end
  end
end

local function paintParticles(gc, ox, oy)
  ox = ox or 0
  oy = oy or 0
  for i = 1, #particles do
    local p = particles[i]
    local t = clamp(p.life / p.maxLife, 0, 1)
    setColor(gc, lerpColor(p.color, BG, t))
    local s = 2 + t * 2
    gc:fillRect(p.x - s/2 + ox, p.y - s/2 + oy, s, s)
  end
end

-- ------------------------------------------------------------
-- bricks
-- ------------------------------------------------------------
local function buildBricks()
  bricks = {}
  local marginX = 6
  local topY = 26
  local gap = 2
  local bw = (W - marginX * 2 - gap * (COLS - 1)) / COLS
  local bh = 9
  for r = 1, ROWS do
    for c = 1, COLS do
      -- higher levels randomly skip a few bricks for variety
      if not (level > 1 and math.random() < 0.08) then
        table.insert(bricks, {
          x = marginX + (c-1) * (bw + gap),
          y = topY + (r-1) * (bh + gap),
          w = bw, h = bh,
          alive = true,
          color = ROW_COLORS[r],
          points = (ROWS - r + 1) * 10,
          hp = 1,
        })
      end
    end
  end
end

local function bricksRemaining()
  local n = 0
  for i = 1, #bricks do if bricks[i].alive then n = n + 1 end end
  return n
end

-- ------------------------------------------------------------
-- paddle / balls / powerups
-- ------------------------------------------------------------
local function resetPaddle()
  paddle.w = 44
  paddle.h = 7
  paddle.x = W/2 - paddle.w/2
  paddle.y = H - 16
  paddle.moveDir = 0
  paddle.moveTimeout = 0
  paddle.speed = 6
end

local function newAttachedBall()
  return { x = paddle.x + paddle.w/2, y = paddle.y - 5, vx = 0, vy = 0, r = 3.5, attached = true }
end

local function ballBaseSpeed()
  local s = 3.2 + (level - 1) * 0.35
  if slowTimer > 0 then s = s * 0.6 end
  return s
end

local function launchBall(b)
  b.attached = false
  b.vx = 0
  b.vy = -ballBaseSpeed()
end

local function resetRound()
  balls = { newAttachedBall() }
  powerups = {}
end

local function startLevel()
  buildBricks()
  resetPaddle()
  resetRound()
end

local function startGame()
  score = 0
  lives = 3
  level = 1
  combo = 0
  comboTimer = 0
  wideTimer, slowTimer = 0, 0
  particles = {}
  startLevel()
  state = "playing"
end

-- ------------------------------------------------------------
-- collisions
-- ------------------------------------------------------------
local function circleRectHit(cx, cy, cr, rx, ry, rw, rh)
  local nx = clamp(cx, rx, rx + rw)
  local ny = clamp(cy, ry, ry + rh)
  local dx, dy = cx - nx, cy - ny
  return (dx*dx + dy*dy) <= (cr*cr), nx, ny
end

local function addScore(pts)
  comboTimer = 40
  combo = combo + 1
  local mult = 1 + combo * 0.1
  score = score + math.floor(pts * mult)
end

local function spawnPowerupMaybe(x, y)
  if math.random() < 0.16 then
    local roll = math.random()
    local t = "wide"
    if roll < 0.28 then t = "multi"
    elseif roll < 0.56 then t = "wide"
    elseif roll < 0.80 then t = "slow"
    else t = "life" end
    table.insert(powerups, { x = x, y = y, vy = 1.6, type = t })
  end
end

local function hitBrick(brick)
  brick.alive = false
  spawnParticles(brick.x + brick.w/2, brick.y + brick.h/2, brick.color, 8)
  shake(1.2, 6)
  addScore(brick.points)
  spawnPowerupMaybe(brick.x + brick.w/2, brick.y + brick.h/2)
end

local function applyPowerup(t)
  if t == "wide" then
    paddle.w = 68
    wideTimer = 260
  elseif t == "slow" then
    slowTimer = 220
  elseif t == "life" then
    lives = lives + 1
  elseif t == "multi" then
    local src = nil
    for i = 1, #balls do if not balls[i].attached then src = balls[i] break end end
    if src then
      table.insert(balls, { x = src.x, y = src.y, vx = src.vx + 1.6, vy = src.vy, r = src.r, attached = false })
      table.insert(balls, { x = src.x, y = src.y, vx = src.vx - 1.6, vy = src.vy, r = src.r, attached = false })
    end
  end
end

-- ------------------------------------------------------------
-- update
-- ------------------------------------------------------------
local function updatePaddle()
  if paddle.moveTimeout > 0 then
    paddle.moveTimeout = paddle.moveTimeout - 1
    paddle.x = paddle.x + paddle.moveDir * paddle.speed
    paddle.x = clamp(paddle.x, 4, W - 4 - paddle.w)
  end
  if wideTimer > 0 then
    wideTimer = wideTimer - 1
    if wideTimer == 0 then paddle.w = 44 end
  end
  if slowTimer > 0 then slowTimer = slowTimer - 1 end
end

local function updateBalls()
  for bi = #balls, 1, -1 do
    local b = balls[bi]
    if b.attached then
      b.x = paddle.x + paddle.w/2
      b.y = paddle.y - b.r - 1
    else
      b.x = b.x + b.vx
      b.y = b.y + b.vy

      if b.x - b.r < 4 then b.x = 4 + b.r; b.vx = -b.vx end
      if b.x + b.r > W - 4 then b.x = W - 4 - b.r; b.vx = -b.vx end
      if b.y - b.r < 16 then b.y = 16 + b.r; b.vy = -b.vy end

      -- paddle
      local hit = circleRectHit(b.x, b.y, b.r, paddle.x, paddle.y, paddle.w, paddle.h)
      if hit and b.vy > 0 then
        local rel = ((b.x - paddle.x) / paddle.w) - 0.5
        local speed = math.sqrt(b.vx*b.vx + b.vy*b.vy)
        local maxAngle = math.rad(65)
        local ang = rel * maxAngle
        b.vx = speed * math.sin(ang)
        b.vy = -math.abs(speed * math.cos(ang))
        b.y = paddle.y - b.r - 0.5
      end

      -- bricks
      for i = 1, #bricks do
        local br = bricks[i]
        if br.alive then
          local hb, nx, ny = circleRectHit(b.x, b.y, b.r, br.x, br.y, br.w, br.h)
          if hb then
            local dx, dy = b.x - nx, b.y - ny
            if math.abs(dx) > math.abs(dy) then b.vx = -b.vx else b.vy = -b.vy end
            hitBrick(br)
            break
          end
        end
      end

      if b.y - b.r > H then
        table.remove(balls, bi)
      end
    end
  end

  if #balls == 0 then
    shake(3, 14)
    lives = lives - 1
    combo = 0
    if lives <= 0 then
      saveHiScore()
      state = "gameover"
    else
      resetPaddle()
      resetRound()
    end
  end
end

local function updatePowerups()
  for i = #powerups, 1, -1 do
    local p = powerups[i]
    p.y = p.y + p.vy
    local hit = p.x > paddle.x and p.x < paddle.x + paddle.w and p.y + 4 > paddle.y and p.y < paddle.y + paddle.h
    if hit then
      applyPowerup(p.type)
      spawnParticles(p.x, p.y, {255,255,255}, 10)
      table.remove(powerups, i)
    elseif p.y > H then
      table.remove(powerups, i)
    end
  end
end

local function updateCombo()
  if comboTimer > 0 then
    comboTimer = comboTimer - 1
    if comboTimer == 0 then combo = 0 end
  end
end

local function updateShake()
  if shakeTimer > 0 then shakeTimer = shakeTimer - 1
  else shakeMag = 0 end
end

local function gameTick()
  if state ~= "playing" then return end
  updatePaddle()
  updateBalls()
  if state ~= "playing" then return end
  updatePowerups()
  updateCombo()
  updateShake()
  updateParticles()

  if bricksRemaining() == 0 then
    level = level + 1
    spawnParticles(W/2, H/2, {255,255,255}, 16)
    startLevel()
  end
end

-- ------------------------------------------------------------
-- paint
-- ------------------------------------------------------------
local function powerupColor(t)
  if t == "wide" then return {90,200,255}
  elseif t == "multi" then return {255,150,70}
  elseif t == "slow" then return {150,120,255}
  else return {120,255,110} end
end

local function paintGame(gc)
  local ox, oy = 0, 0
  if shakeMag > 0 then
    ox = (math.random() * 2 - 1) * shakeMag
    oy = (math.random() * 2 - 1) * shakeMag
  end

  setColor(gc, BG)
  gc:fillRect(0, 0, W, H)

  -- bricks
  for i = 1, #bricks do
    local br = bricks[i]
    if br.alive then
      setColor(gc, br.color)
      gc:fillRect(br.x + ox, br.y + oy, br.w, br.h)
    end
  end

  -- powerups
  for i = 1, #powerups do
    local p = powerups[i]
    setColor(gc, powerupColor(p.type))
    gc:fillRect(p.x - 4 + ox, p.y - 4 + oy, 8, 8)
  end

  -- paddle
  setColor(gc, 230, 230, 240)
  gc:fillRect(paddle.x + ox, paddle.y + oy, paddle.w, paddle.h)

  -- balls
  setColor(gc, 255, 255, 255)
  for i = 1, #balls do
    local b = balls[i]
    gc:fillRect(b.x - b.r + ox, b.y - b.r + oy, b.r*2, b.r*2)
  end

  paintParticles(gc, ox, oy)

  -- HUD
  setColor(gc, 255, 255, 255)
  gc:drawString("Score " .. score, 4, 2, "top")
  gc:drawString("Lv " .. level, W/2 - 14, 2, "top")
  gc:drawString("Lives " .. lives, W - 70, 2, "top")
  if combo > 1 then
    setColor(gc, 255, 220, 60)
    gc:drawString("Combo x" .. combo, W/2 - 30, 14, "top")
  end
end

local function paintTitle(gc)
  setColor(gc, BG)
  gc:fillRect(0, 0, W, H)
  setColor(gc, 255, 255, 255)
  gc:drawString("BRICK BLITZ", W/2 - 62, 40, "top")
  setColor(gc, 150, 150, 165)
  gc:drawString("Press ENTER to play", W/2 - 78, 66, "top")
  gc:drawString("left/right = move", W/2 - 72, 90, "top")
  gc:drawString("enter = launch ball", W/2 - 78, 106, "top")
  setColor(gc, 255, 220, 60)
  gc:drawString("High Score: " .. hiScore, W/2 - 60, 140, "top")
end

local function paintGameover(gc)
  paintGame(gc)
  setColor(gc, 10, 10, 15)
  gc:fillRect(W/2 - 90, H/2 - 40, 180, 90)
  setColor(gc, 255, 90, 90)
  gc:drawRect(W/2 - 90, H/2 - 40, 180, 90)
  setColor(gc, 255, 255, 255)
  gc:drawString("GAME OVER", W/2 - 48, H/2 - 30, "top")
  gc:drawString("Score: " .. score, W/2 - 46, H/2 - 10, "top")
  if score >= hiScore and score > 0 then
    setColor(gc, 255, 220, 60)
    gc:drawString("NEW HIGH SCORE!", W/2 - 62, H/2 + 6, "top")
  end
  setColor(gc, 150, 150, 165)
  gc:drawString("Enter = retry", W/2 - 48, H/2 + 26, "top")
end

local function paintPaused(gc)
  paintGame(gc)
  setColor(gc, 10, 10, 15)
  gc:fillRect(W/2 - 70, H/2 - 30, 140, 60)
  setColor(gc, 90, 200, 255)
  gc:drawRect(W/2 - 70, H/2 - 30, 140, 60)
  setColor(gc, 255, 255, 255)
  gc:drawString("PAUSED", W/2 - 30, H/2 - 20, "top")
  setColor(gc, 150, 150, 165)
  gc:drawString("esc = resume", W/2 - 46, H/2)
  gc:drawString("enter = title", W/2 - 46, H/2 + 16)
end

-- ------------------------------------------------------------
-- input
-- ------------------------------------------------------------
local function keyDown(key)
  if state ~= "playing" then return end
  if key == "left" then paddle.moveDir = -1; paddle.moveTimeout = 4
  elseif key == "right" then paddle.moveDir = 1; paddle.moveTimeout = 4
  end
end

local function enterAction()
  if state == "title" then
    startGame()
  elseif state == "playing" then
    for i = 1, #balls do
      if balls[i].attached then launchBall(balls[i]) end
    end
  elseif state == "gameover" then
    state = "title"
  elseif state == "paused" then
    state = "title"
  end
end

local function escAction()
  if state == "playing" then state = "paused"
  elseif state == "paused" then state = "playing"
  end
end

-- ------------------------------------------------------------
-- global dispatch
-- ------------------------------------------------------------
function on.construction()
  local ok, ms = pcall(function() return timer.getMilliSecCounter() end)
  math.randomseed(ok and ms or 7)
  loadHiScore()
  resetPaddle()
end

function on.resize()
  W = platform.window:width()
  H = platform.window:height()
  platform.window:invalidate()
end

function on.paint(gc)
  if state == "title" then paintTitle(gc)
  elseif state == "playing" then paintGame(gc)
  elseif state == "paused" then paintPaused(gc)
  elseif state == "gameover" then paintGameover(gc)
  end
end

function on.timer()
  gameTick()
  platform.window:invalidate()
end

function on.arrowKey(key)
  keyDown(key)
end

function on.enterKey()
  enterAction()
  platform.window:invalidate()
end

function on.charIn(ch)
  if ch == " " then enterAction() end
end

function on.escapeKey()
  escAction()
  platform.window:invalidate()
end

timer.start(0.04) -- ~25 fps
