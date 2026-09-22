-- ============================================================
--  MAZE MUNCHER
--  An original maze-chase game for TI-Nspire CX II
--  smooth grid movement / 4 distinct AI personalities
--  power pellets / combo scoring / fruit bonus / tunnel wrap
--  achievements / persistent stats
-- ============================================================

platform.apilevel = "2.5"

local W, H = 318, 212
local CELL = 10
local COLS, ROWS = 25, 17
local TUNNEL_ROW = 8
local OFFX, OFFY = 34, 20

local BG = { 8, 8, 16 }
local WALL_COLOR = { 40, 50, 130 }

local function setColor(gc, c, g, b)
  if g ~= nil then gc:setColorRGB(c, g, b)
  else gc:setColorRGB(c[1], c[2], c[3]) end
end
local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi else return v end end
local function lerp(a, b, t) return a + (b - a) * t end
local function lerpColor(c, bg, t)
  return { math.floor(lerp(bg[1], c[1], t)), math.floor(lerp(bg[2], c[2], t)), math.floor(lerp(bg[3], c[3], t)) }
end
local function roundi(x) return math.floor(x + 0.5) end
local function dist2(r1, c1, r2, c2) local dr, dc = r1-r2, c1-c2 return dr*dr + dc*dc end

local function cellPx(row, col) return OFFX + col * CELL, OFFY + row * CELL end

-- forward-declared runtime state (referenced by functions defined earlier
-- in the file than the section that formally initializes them)
local score = 0
local lives = 3
local level = 1
local livesLostThisLevel = 0

-- state: "title" | "playing" | "paused" | "gameover" | "achievements"
local state = "title"

-- ------------------------------------------------------------
-- difficulty
-- ------------------------------------------------------------
local DIFFS = {
  { name = "Easy",   lives = 4, ghostSpeedMult = 0.85, scoreMult = 0.8 },
  { name = "Normal", lives = 3, ghostSpeedMult = 1.0,  scoreMult = 1.0 },
  { name = "Hard",   lives = 2, ghostSpeedMult = 1.2,  scoreMult = 1.4 },
}
local diffIndex = 2
local function diff() return DIFFS[diffIndex] end

-- ------------------------------------------------------------
-- persistent stats / achievements
-- ------------------------------------------------------------
local hiScore = 0
local stats = { totalDots = 0, ghostsEaten = 0, fruitsEaten = 0, gamesPlayed = 0, bestLevel = 0 }
local ACH_LIST = {
  { id = "dotdevourer", name = "Dot Devourer",  desc = "Eat 300 dots total" },
  { id = "ghosthunter",  name = "Ghost Hunter",  desc = "Eat 50 ghosts total" },
  { id = "fruitfan",     name = "Fruit Fan",     desc = "Eat 10 fruits total" },
  { id = "survivor",     name = "Survivor",      desc = "Reach level 5" },
  { id = "perfectionist",name = "Perfectionist", desc = "Clear a level without losing a life" },
  { id = "highroller",   name = "High Roller",   desc = "Score 10000+ in one game" },
}
local achUnlocked = {}
local achToast = nil

local function loadPersist()
  local ok, v = pcall(function() return var.recall("mm_hiscore") end)
  hiScore = (ok and type(v) == "number") and v or 0
  local ok2, s = pcall(function() return var.recall("mm_stats") end)
  if ok2 and type(s) == "string" then
    for key, val in s:gmatch("(%a+)=(%d+)") do
      if stats[key] ~= nil then stats[key] = tonumber(val) end
    end
  end
  for i = 1, #ACH_LIST do
    local id = ACH_LIST[i].id
    local okA, va = pcall(function() return var.recall("mm_ach_" .. id) end)
    achUnlocked[id] = (okA and va == 1) or false
  end
end

local function statsToString()
  local parts = {}
  for k, v in pairs(stats) do table.insert(parts, k .. "=" .. math.floor(v)) end
  return table.concat(parts, ",")
end

local function savePersist() pcall(function() var.store("mm_stats", statsToString()) end) end

local function saveHiScore()
  if score > hiScore then
    hiScore = score
    pcall(function() var.store("mm_hiscore", hiScore) end)
  end
end

local function unlockAch(id, name)
  if not achUnlocked[id] then
    achUnlocked[id] = true
    pcall(function() var.store("mm_ach_" .. id, 1) end)
    achToast = { text = "Unlocked: " .. name, timer = 90 }
  end
end

local function checkAchievements(ctx)
  if stats.totalDots >= 300 then unlockAch("dotdevourer", "Dot Devourer") end
  if stats.ghostsEaten >= 50 then unlockAch("ghosthunter", "Ghost Hunter") end
  if stats.fruitsEaten >= 10 then unlockAch("fruitfan", "Fruit Fan") end
  if stats.bestLevel >= 5 then unlockAch("survivor", "Survivor") end
  if ctx and ctx.perfectLevel then unlockAch("perfectionist", "Perfectionist") end
  if ctx and ctx.score and ctx.score >= 10000 then unlockAch("highroller", "High Roller") end
end

-- ------------------------------------------------------------
-- maze generation
-- ------------------------------------------------------------
local grid = {}
local totalDots, dotsEaten = 0, 0

local function buildMaze()
  grid = {}
  for r = 0, ROWS - 1 do
    grid[r] = {}
    for c = 0, COLS - 1 do
      if r == 0 or r == ROWS - 1 or c == 0 or c == COLS - 1 then
        grid[r][c] = "wall"
      elseif r % 2 == 0 and c % 2 == 0 then
        grid[r][c] = "wall"
      else
        grid[r][c] = "dot"
      end
    end
  end
  -- tunnel opening (mid row, both edges)
  grid[TUNNEL_ROW][0] = "dot"
  grid[TUNNEL_ROW][COLS-1] = "dot"

  -- ghost house box: rows 6-10, cols 10-14, gate at (6,12)
  for r = 6, 10 do
    for c = 10, 14 do
      if r == 6 and c == 12 then
        grid[r][c] = "gate"
      elseif r == 6 or r == 10 or c == 10 or c == 14 then
        grid[r][c] = "wall"
      else
        grid[r][c] = "empty"
      end
    end
  end

  -- power pellets, four corners
  grid[1][1] = "power"; grid[1][COLS-2] = "power"
  grid[ROWS-2][1] = "power"; grid[ROWS-2][COLS-2] = "power"

  -- clear player spawn cell (no free point at start)
  grid[13][12] = "empty"

  totalDots = 0
  for r = 0, ROWS - 1 do
    for c = 0, COLS - 1 do
      if grid[r][c] == "dot" or grid[r][c] == "power" then totalDots = totalDots + 1 end
    end
  end
  dotsEaten = 0
end

local function isOpenCell(row, col)
  if row < 0 or row >= ROWS then return false end
  if col < 0 or col >= COLS then return row == TUNNEL_ROW end
  return grid[row][col] ~= "wall"
end

-- ------------------------------------------------------------
-- entities
-- ------------------------------------------------------------
local player = {}
local ghosts = {}
local fruit = { active = false, timer = 0, col = 12, row = 11, spawnedAt = {} }
local particles = {}
local popups = {}
local shakeTimer, shakeMag = 0, 0
local flashTimer, flashColorV = 0, {255,255,255}

local frightTimer = 0
local frightCombo = 0
local baseFrightDuration = 360 -- ticks, shrinks with level
local MODE_SCHEDULE = { {"scatter",7*25}, {"chase",20*25}, {"scatter",7*25}, {"chase",20*25}, {"scatter",5*25}, {"chase",999999} }
local modeIdx, modeTimer = 1, MODE_SCHEDULE[1][2]

local function scheduleMode() return MODE_SCHEDULE[modeIdx][1] end

local function resetSchedule()
  modeIdx, modeTimer = 1, MODE_SCHEDULE[1][2]
end

local function isAligned(e)
  return math.abs(e.col - roundi(e.col)) < 0.06 and math.abs(e.row - roundi(e.row)) < 0.06
end

local DIRLIST = { {dx=0,dy=-1}, {dx=0,dy=1}, {dx=-1,dy=0}, {dx=1,dy=0} }

local function initPlayer()
  player = { col = 12, row = 13, dir = {dx=0,dy=0}, nextDir = {dx=0,dy=0}, speed = 0.105, animTimer = 0, mouthOpen = true }
end

local function ghostSpec(idx)
  if idx == 1 then return { color = {255,70,70},  personality = "chaser",   corner = {row=1,col=COLS-2} }
  elseif idx == 2 then return { color = {255,150,220}, personality = "ambusher", corner = {row=1,col=1} }
  elseif idx == 3 then return { color = {110,220,255}, personality = "flanker", corner = {row=ROWS-2,col=COLS-2} }
  else return { color = {255,170,60}, personality = "shy", corner = {row=ROWS-2,col=1} } end
end

local HOUSE_SPOTS = { {row=8,col=11}, {row=8,col=12}, {row=8,col=13}, {row=7,col=12} }

local function initGhosts()
  ghosts = {}
  for i = 1, 4 do
    local spec = ghostSpec(i)
    local spot = HOUSE_SPOTS[i]
    table.insert(ghosts, {
      col = spot.col, row = spot.row, dir = {dx=0,dy=-1},
      color = spec.color, personality = spec.personality, corner = spec.corner,
      speedBase = 0.095, state = "house", releaseTimer = (i-1) * 70 + 40,
      bobDir = 1,
    })
  end
end

-- ------------------------------------------------------------
-- particles / shake / flash / popups
-- ------------------------------------------------------------
local function spawnParticles(x, y, color, count)
  for i = 1, count do
    local ang = math.random() * math.pi * 2
    local spd = 1 + math.random() * 2.2
    table.insert(particles, { x=x, y=y, vx=math.cos(ang)*spd, vy=math.sin(ang)*spd, life=18+math.random(0,8), maxLife=26, color=color })
  end
end
local function shake(mag, dur) shakeMag = math.max(shakeMag, mag); shakeTimer = math.max(shakeTimer, dur) end
local function flash(color, dur) flashColorV = color; flashTimer = dur end
local function popup(x, y, text, color) table.insert(popups, { x=x, y=y, text=text, color=color, timer=40 }) end

local function updateParticles()
  for i = #particles, 1, -1 do
    local p = particles[i]
    p.x=p.x+p.vx; p.y=p.y+p.vy; p.vy=p.vy+0.1; p.life=p.life-1
    if p.life <= 0 then table.remove(particles, i) end
  end
end
local function updatePopups()
  for i = #popups, 1, -1 do
    local p = popups[i]
    p.y = p.y - 0.4; p.timer = p.timer - 1
    if p.timer <= 0 then table.remove(popups, i) end
  end
end
local function paintExtras(gc, ox, oy)
  for i = 1, #particles do
    local p = particles[i]
    local t = clamp(p.life / p.maxLife, 0, 1)
    setColor(gc, lerpColor(p.color, BG, t))
    local s = 2 + t * 2
    gc:fillRect(p.x - s/2 + ox, p.y - s/2 + oy, s, s)
  end
  for i = 1, #popups do
    local p = popups[i]
    setColor(gc, p.color)
    gc:drawString(p.text, p.x + ox, p.y + oy, "top")
  end
end

-- ------------------------------------------------------------
-- movement
-- ------------------------------------------------------------
local function wrapCol(e)
  if e.col < 0 then e.col = e.col + COLS
  elseif e.col >= COLS then e.col = e.col - COLS end
end

local function pickPlayerDir()
  if isAligned(player) then
    player.col, player.row = roundi(player.col), roundi(player.row)
    if (player.nextDir.dx ~= 0 or player.nextDir.dy ~= 0) and isOpenCell(player.row + player.nextDir.dy, player.col + player.nextDir.dx) then
      player.dir = player.nextDir
    end
    if not isOpenCell(player.row + player.dir.dy, player.col + player.dir.dx) then
      player.dir = {dx=0,dy=0}
    end
  end
end

local function updatePlayerMove()
  pickPlayerDir()
  player.col = player.col + player.dir.dx * player.speed
  player.row = player.row + player.dir.dy * player.speed
  wrapCol(player)
  player.animTimer = player.animTimer + 1
  if player.animTimer % 6 == 0 then player.mouthOpen = not player.mouthOpen end
end

local function ghostTargetFor(g)
  local pc, pr = roundi(player.col), roundi(player.row)
  if g.personality == "chaser" then
    return { row = pr, col = pc }
  elseif g.personality == "ambusher" then
    local ac = pc + player.dir.dx * 4
    local ar = pr + player.dir.dy * 4
    return { row = clamp(ar, 0, ROWS-1), col = clamp(ac, 0, COLS-1) }
  elseif g.personality == "flanker" then
    local anchor = ghosts[1]
    local ac = pc + player.dir.dx * 2
    local ar = pr + player.dir.dy * 2
    local tr = anchor.row + 2 * (ar - anchor.row)
    local tc = anchor.col + 2 * (ac - anchor.col)
    return { row = clamp(tr, 0, ROWS-1), col = clamp(tc, 0, COLS-1) }
  else -- shy
    local d2 = dist2(g.row, g.col, pr, pc)
    if d2 > 64 then return { row = pr, col = pc }
    else return g.corner end
  end
end

local function pickGhostDir(g)
  if not isAligned(g) then return end
  g.col, g.row = roundi(g.col), roundi(g.row)

  local target
  if g.state == "eaten" then
    target = { row = 6, col = 12 } -- gate
  elseif frightTimer > 0 and g.state == "active" then
    target = nil -- random
  elseif scheduleMode() == "scatter" and g.state == "active" then
    target = g.corner
  else
    target = ghostTargetFor(g)
  end

  local candidates = {}
  for i = 1, #DIRLIST do
    local d = DIRLIST[i]
    local isReverse = (d.dx == -g.dir.dx and d.dy == -g.dir.dy) and (g.dir.dx ~= 0 or g.dir.dy ~= 0)
    if isOpenCell(g.row + d.dy, g.col + d.dx) and not isReverse then
      table.insert(candidates, d)
    end
  end
  if #candidates == 0 then
    -- dead end: allow reverse
    for i = 1, #DIRLIST do
      local d = DIRLIST[i]
      if isOpenCell(g.row + d.dy, g.col + d.dx) then table.insert(candidates, d) end
    end
  end

  if #candidates == 0 then return end

  if target == nil then
    g.dir = candidates[math.random(1, #candidates)]
  else
    local best, bestD = candidates[1], math.huge
    for i = 1, #candidates do
      local d = candidates[i]
      local nr, nc = g.row + d.dy, g.col + d.dx
      local dd = dist2(nr, nc, target.row, target.col)
      if dd < bestD then bestD = dd; best = d end
    end
    g.dir = best
  end
end

local function ghostSpeed(g)
  local s = g.speedBase * diff().ghostSpeedMult * (1 + (level - 1) * 0.04)
  if g.state == "eaten" then return s * 2.2 end
  if frightTimer > 0 and g.state == "active" then return s * 0.55 end
  return s
end

local function updateGhostMove(g)
  if g.state == "house" then
    g.row = g.row + g.bobDir * 0.03
    if g.row > 8.4 then g.bobDir = -1 elseif g.row < 7.6 then g.bobDir = 1 end
    g.releaseTimer = g.releaseTimer - 1
    if g.releaseTimer <= 0 then
      g.state = "active"
      g.row, g.col = 5, 12 -- pop out just above the gate
      g.dir = {dx=0,dy=-1}
    end
    return
  end

  pickGhostDir(g)
  local spd = ghostSpeed(g)
  g.col = g.col + g.dir.dx * spd
  g.row = g.row + g.dir.dy * spd
  wrapCol(g)

  if g.state == "eaten" and dist2(g.row, g.col, 6, 12) < 0.3 then
    g.state = "house"
    g.row, g.col = 8, 12
    g.releaseTimer = 30
  end
end

-- ------------------------------------------------------------
-- game flow
-- ------------------------------------------------------------
local function resetPositions()
  initPlayer()
  initGhosts()
end

local function startLevel()
  buildMaze()
  resetPositions()
  frightTimer = 0
  livesLostThisLevel = 0
  fruit.active = false
  fruit.spawnedAt = {}
end

local function startGame()
  score = 0
  lives = diff().lives
  level = 1
  particles, popups = {}, {}
  stats.gamesPlayed = stats.gamesPlayed + 1
  resetSchedule()
  startLevel()
  state = "playing"
end

local function loseLife()
  shake(3, 14)
  lives = lives - 1
  livesLostThisLevel = livesLostThisLevel + 1
  if lives <= 0 then
    saveHiScore(); savePersist(); checkAchievements({ score = score })
    state = "gameover"
  else
    resetPositions()
    resetSchedule()
    frightTimer = 0
  end
end

local function eatDot(row, col)
  local cell = grid[row][col]
  if cell == "dot" then
    grid[row][col] = "empty"
    score = score + 10
    dotsEaten = dotsEaten + 1
    stats.totalDots = stats.totalDots + 1
  elseif cell == "power" then
    grid[row][col] = "empty"
    score = score + 50
    dotsEaten = dotsEaten + 1
    stats.totalDots = stats.totalDots + 1
    frightTimer = math.max(60, baseFrightDuration - (level-1) * 20)
    frightCombo = 0
    shake(1, 6)
    for i = 1, #ghosts do
      if ghosts[i].state == "active" then ghosts[i].dir = {dx=-ghosts[i].dir.dx, dy=-ghosts[i].dir.dy} end
    end
  end
end

local FRUIT_SCORE = 100
local function updateFruitSpawn()
  if not fruit.active then
    if dotsEaten >= 30 and not fruit.spawnedAt[1] then
      fruit.spawnedAt[1] = true; fruit.active = true; fruit.timer = 280
    elseif dotsEaten >= 120 and not fruit.spawnedAt[2] then
      fruit.spawnedAt[2] = true; fruit.active = true; fruit.timer = 280
    end
  else
    fruit.timer = fruit.timer - 1
    if fruit.timer <= 0 then fruit.active = false end
    if roundi(player.col) == fruit.col and roundi(player.row) == fruit.row and isAligned(player) then
      fruit.active = false
      local pts = FRUIT_SCORE * level
      score = score + pts
      stats.fruitsEaten = stats.fruitsEaten + 1
      local x, y = cellPx(fruit.row, fruit.col)
      popup(x, y, "+" .. pts, {255,220,60})
      spawnParticles(x+5, y+5, {255,180,60}, 10)
    end
  end
end

local function eatGhost(g)
  frightCombo = frightCombo + 1
  local table_ = {200,400,800,1600}
  local pts = table_[math.min(frightCombo, 4)]
  score = score + pts
  stats.ghostsEaten = stats.ghostsEaten + 1
  g.state = "eaten"
  local x, y = cellPx(g.row, g.col)
  popup(x, y, "+" .. pts, {200,240,255})
  spawnParticles(x+5, y+5, {220,220,255}, 12)
  shake(1.5, 8)
  flash({255,255,255}, 4)
end

local function updateCollisions()
  for i = 1, #ghosts do
    local g = ghosts[i]
    if g.state == "active" and dist2(g.row, g.col, player.row, player.col) < 0.35 then
      if frightTimer > 0 then
        eatGhost(g)
      else
        loseLife()
        return
      end
    end
  end
end

local function updateModeSchedule()
  if frightTimer > 0 then
    frightTimer = frightTimer - 1
    return
  end
  modeTimer = modeTimer - 1
  if modeTimer <= 0 and modeIdx < #MODE_SCHEDULE then
    modeIdx = modeIdx + 1
    modeTimer = MODE_SCHEDULE[modeIdx][2]
    for i = 1, #ghosts do
      if ghosts[i].state == "active" then ghosts[i].dir = {dx=-ghosts[i].dir.dx, dy=-ghosts[i].dir.dy} end
    end
  end
end

local function updateShakeFlash()
  if shakeTimer > 0 then shakeTimer = shakeTimer - 1 else shakeMag = 0 end
  if flashTimer > 0 then flashTimer = flashTimer - 1 end
  if achToast then
    achToast.timer = achToast.timer - 1
    if achToast.timer <= 0 then achToast = nil end
  end
end

local function gameTick()
  if state ~= "playing" then return end
  updatePlayerMove()
  if isAligned(player) then eatDot(roundi(player.row), roundi(player.col)) end
  for i = 1, #ghosts do updateGhostMove(ghosts[i]) end
  updateCollisions()
  if state ~= "playing" then return end
  updateFruitSpawn()
  updateModeSchedule()
  updateShakeFlash()
  updateParticles()
  updatePopups()

  if dotsEaten >= totalDots then
    level = level + 1
    if level > stats.bestLevel then stats.bestLevel = level end
    if livesLostThisLevel == 0 then checkAchievements({ perfectLevel = true }) end
    spawnParticles(W/2, H/2, {255,255,255}, 16)
    resetSchedule()
    startLevel()
  end
end

-- ------------------------------------------------------------
-- paint
-- ------------------------------------------------------------
local function paintMaze(gc, ox, oy)
  for r = 0, ROWS - 1 do
    for c = 0, COLS - 1 do
      local cell = grid[r][c]
      local x, y = cellPx(r, c)
      x, y = x + ox, y + oy
      if cell == "wall" then
        setColor(gc, WALL_COLOR)
        gc:fillRect(x, y, CELL, CELL)
      elseif cell == "dot" then
        setColor(gc, 255, 220, 170)
        gc:fillRect(x + CELL/2 - 1, y + CELL/2 - 1, 2, 2)
      elseif cell == "power" then
        local pulse = 3 + math.floor((player.animTimer % 20) / 10) * 1
        setColor(gc, 255, 240, 120)
        gc:fillRect(x + CELL/2 - pulse/2, y + CELL/2 - pulse/2, pulse, pulse)
      end
    end
  end
end

local function paintPlayer(gc, ox, oy)
  local x, y = cellPx(player.row, player.col)
  x, y = x + ox, y + oy
  setColor(gc, 255, 230, 60)
  gc:fillRect(x + 1, y + 1, CELL - 2, CELL - 2)
  if player.mouthOpen then
    setColor(gc, BG)
    local mx, my, mw, mh = x + 1, y + 1, CELL-2, CELL-2
    if player.dir.dx == 1 then gc:fillRect(x + CELL - 4, y + 3, 4, CELL - 6)
    elseif player.dir.dx == -1 then gc:fillRect(x, y + 3, 4, CELL - 6)
    elseif player.dir.dy == 1 then gc:fillRect(x + 3, y + CELL - 4, CELL - 6, 4)
    elseif player.dir.dy == -1 then gc:fillRect(x + 3, y, CELL - 6, 4)
    else gc:fillRect(x + CELL - 4, y + 3, 4, CELL - 6) end
  end
end

local function paintGhosts(gc, ox, oy)
  for i = 1, #ghosts do
    local g = ghosts[i]
    if g.state ~= "house" or true then
      local x, y = cellPx(g.row, g.col)
      x, y = x + ox, y + oy
      if g.state == "eaten" then
        setColor(gc, 255,255,255)
        gc:fillRect(x + 2, y + 3, 2, 2)
        gc:fillRect(x + CELL - 4, y + 3, 2, 2)
      else
        local col = g.color
        if frightTimer > 0 and g.state == "active" then
          if frightTimer < 80 and (player.animTimer % 10 < 5) then col = {255,255,255} else col = {60,60,220} end
        end
        setColor(gc, col)
        gc:fillRect(x + 1, y + 1, CELL - 2, CELL - 2)
        setColor(gc, 255,255,255)
        gc:fillRect(x + 2, y + 3, 2, 2)
        gc:fillRect(x + CELL - 4, y + 3, 2, 2)
      end
    end
  end
end

local function paintFruit(gc, ox, oy)
  if fruit.active then
    local x, y = cellPx(fruit.row, fruit.col)
    x, y = x + ox, y + oy
    setColor(gc, 255, 90, 90)
    gc:fillRect(x + 2, y + 2, CELL - 4, CELL - 4)
  end
end

local function paintGame(gc)
  local ox, oy = 0, 0
  if shakeMag > 0 then
    ox = (math.random() * 2 - 1) * shakeMag
    oy = (math.random() * 2 - 1) * shakeMag
  end
  if flashTimer > 0 then setColor(gc, flashColorV) else setColor(gc, BG) end
  gc:fillRect(0, 0, W, H)

  paintMaze(gc, ox, oy)
  paintFruit(gc, ox, oy)
  paintGhosts(gc, ox, oy)
  paintPlayer(gc, ox, oy)
  paintExtras(gc, ox, oy)

  setColor(gc, 255,255,255)
  gc:drawString("Score " .. score, 2, 2, "top")
  gc:drawString("Lv " .. level, W/2 - 10, 2, "top")
  gc:drawString("Lives " .. lives, W - 62, 2, "top")
  if achToast then
    setColor(gc, 10,10,15)
    gc:fillRect(W/2 - 80, H - 14, 160, 14)
    setColor(gc, 255, 220, 60)
    gc:drawString(achToast.text, W/2 - 74, H - 13, "top")
  end
end

local function paintTitle(gc)
  setColor(gc, BG)
  gc:fillRect(0, 0, W, H)
  setColor(gc, 255, 230, 60)
  gc:drawString("MAZE MUNCHER", W/2 - 64, 16, "top")
  setColor(gc, 150, 150, 165)
  gc:drawString("ENTER = play", W/2 - 56, 40, "top")
  gc:drawString("arrows = move (buffered)", W/2 - 94, 56, "top")
  gc:drawString("A = view achievements", W/2 - 90, 70, "top")
  setColor(gc, 90,200,255)
  gc:drawString("Difficulty: < " .. diff().name .. " >", W/2 - 60, 94, "top")
  setColor(gc, 255, 220, 60)
  gc:drawString("High Score: " .. hiScore, W/2 - 58, 124, "top")
  setColor(gc, 150,150,165)
  gc:drawString("Best level " .. stats.bestLevel .. "  Dots " .. stats.totalDots, W/2 - 84, 140, "top")

  -- little decorative ghosts
  local colors = {{255,70,70},{255,150,220},{110,220,255},{255,170,60}}
  for i = 1, 4 do
    setColor(gc, colors[i])
    gc:fillRect(W/2 - 76 + (i-1)*38, 164, 12, 12)
  end
end

local function paintAchievements(gc)
  setColor(gc, BG)
  gc:fillRect(0, 0, W, H)
  setColor(gc, 255,255,255)
  gc:drawString("ACHIEVEMENTS", W/2 - 60, 4, "top")
  for i = 1, #ACH_LIST do
    local a = ACH_LIST[i]
    local y = 22 + (i-1) * 26
    if achUnlocked[a.id] then setColor(gc, 120,255,120) else setColor(gc, 90,90,100) end
    gc:drawString((achUnlocked[a.id] and "[x] " or "[ ] ") .. a.name, 10, y, "top")
    setColor(gc, 140,140,150)
    gc:drawString(a.desc, 10, y + 12, "top")
  end
  setColor(gc, 150,150,165)
  gc:drawString("esc = back", W/2 - 34, H - 14, "top")
end

local function paintGameover(gc)
  paintGame(gc)
  setColor(gc, 10, 10, 15)
  gc:fillRect(W/2 - 95, H/2 - 46, 190, 100)
  setColor(gc, 255, 90, 90)
  gc:drawRect(W/2 - 95, H/2 - 46, 190, 100)
  setColor(gc, 255, 255, 255)
  gc:drawString("GAME OVER", W/2 - 48, H/2 - 36, "top")
  gc:drawString("Score: " .. score, W/2 - 46, H/2 - 16, "top")
  gc:drawString("Level reached: " .. level, W/2 - 70, H/2, "top")
  if score >= hiScore and score > 0 then
    setColor(gc, 255, 220, 60)
    gc:drawString("NEW HIGH SCORE!", W/2 - 62, H/2 + 18, "top")
  end
  setColor(gc, 150, 150, 165)
  gc:drawString("Enter = title", W/2 - 46, H/2 + 34, "top")
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
local function setNextDir(dx, dy)
  if state ~= "playing" then return end
  player.nextDir = {dx=dx, dy=dy}
end

local function keyDown(key)
  if state == "title" then
    if key == "left" then diffIndex = diffIndex - 1; if diffIndex < 1 then diffIndex = #DIFFS end end
    if key == "right" then diffIndex = diffIndex + 1; if diffIndex > #DIFFS then diffIndex = 1 end end
    return
  end
  if key == "up" then setNextDir(0,-1)
  elseif key == "down" then setNextDir(0,1)
  elseif key == "left" then setNextDir(-1,0)
  elseif key == "right" then setNextDir(1,0)
  end
end

local function enterAction()
  if state == "title" then startGame()
  elseif state == "gameover" then state = "title"
  elseif state == "paused" then state = "title"
  elseif state == "achievements" then state = "title"
  end
end

local function escAction()
  if state == "playing" then state = "paused"
  elseif state == "paused" then state = "playing"
  elseif state == "achievements" then state = "title"
  end
end

-- ------------------------------------------------------------
-- global dispatch
-- ------------------------------------------------------------
function on.construction()
  local ok, ms = pcall(function() return timer.getMilliSecCounter() end)
  math.randomseed(ok and ms or 11)
  loadPersist()
  buildMaze()
  resetPositions()
end

function on.resize()
  W = platform.window:width()
  H = platform.window:height()
  OFFX = math.floor((W - COLS * CELL) / 2)
  OFFY = 20
  platform.window:invalidate()
end

function on.paint(gc)
  if state == "title" then paintTitle(gc)
  elseif state == "playing" then paintGame(gc)
  elseif state == "paused" then paintPaused(gc)
  elseif state == "gameover" then paintGameover(gc)
  elseif state == "achievements" then paintAchievements(gc)
  end
end

function on.timer()
  gameTick()
  platform.window:invalidate()
end

function on.arrowKey(key) keyDown(key) end

function on.enterKey()
  enterAction()
  platform.window:invalidate()
end

function on.charIn(ch)
  if (ch == "a" or ch == "A") and state == "title" then state = "achievements" end
end

function on.escapeKey()
  escAction()
  platform.window:invalidate()
end

timer.start(0.04) -- ~25 fps
