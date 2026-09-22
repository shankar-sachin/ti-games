-- ============================================================
--  NSPIRE GAME HUB
--  Snek Classic / Tetroid / Geo Rush, all in one dumb little menu
--  Built for TI-Nspire CX II (Lua scripting, apilevel 2.5)
-- ============================================================

platform.apilevel = "2.5"

local W, H = 318, 212

local state = "menu"          -- "menu" | "snake" | "tetroid" | "georush"
local menuItems = { "Snek Classic", "Tetroid", "Geo Rush" }
local menuIndex = 1

local function setColor(gc, r, g, b) gc:setColorRGB(r, g, b) end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

-- ============================================================
--  SNEK CLASSIC
-- ============================================================
local snake = {}

local function snakeInit()
  snake.cell = 10
  snake.cols = math.floor(W / snake.cell)
  snake.rows = math.floor((H - 20) / snake.cell) -- leave a strip for the score
  snake.offY = 20
  snake.body = { { x = 5, y = 5 }, { x = 4, y = 5 }, { x = 3, y = 5 } }
  snake.dir = { x = 1, y = 0 }
  snake.nextDir = { x = 1, y = 0 }
  snake.food = { x = 10, y = 10 }
  snake.score = 0
  snake.dead = false
  snake.speed = 3     -- lower = faster; gates against the global ~20fps tick
  snake.frame = 0
end

local function snakePlaceFood()
  snake.food = { x = math.random(0, snake.cols - 1), y = math.random(0, snake.rows - 1) }
end

local function snakeTick()
  if snake.dead then return end
  snake.frame = snake.frame + 1
  if snake.frame % snake.speed ~= 0 then return end

  snake.dir = snake.nextDir
  local head = snake.body[1]
  local nh = { x = head.x + snake.dir.x, y = head.y + snake.dir.y }

  if nh.x < 0 then nh.x = snake.cols - 1 end
  if nh.x >= snake.cols then nh.x = 0 end
  if nh.y < 0 then nh.y = snake.rows - 1 end
  if nh.y >= snake.rows then nh.y = 0 end

  for i = 1, #snake.body do
    local seg = snake.body[i]
    if seg.x == nh.x and seg.y == nh.y then
      snake.dead = true
      return
    end
  end

  table.insert(snake.body, 1, nh)
  if nh.x == snake.food.x and nh.y == snake.food.y then
    snake.score = snake.score + 1
    snakePlaceFood()
  else
    table.remove(snake.body)
  end
end

local function snakePaint(gc)
  setColor(gc, 12, 12, 22)
  gc:fillRect(0, 0, W, H)

  setColor(gc, 255, 60, 60)
  gc:fillRect(snake.food.x * snake.cell, snake.offY + snake.food.y * snake.cell, snake.cell - 1, snake.cell - 1)

  setColor(gc, 60, 255, 120)
  for i = 1, #snake.body do
    local seg = snake.body[i]
    gc:fillRect(seg.x * snake.cell, snake.offY + seg.y * snake.cell, snake.cell - 1, snake.cell - 1)
  end

  setColor(gc, 255, 255, 255)
  gc:drawString("Score: " .. snake.score, 4, 2, "top")
  gc:drawString("esc = menu", W - 90, 2, "top")

  if snake.dead then
    setColor(gc, 255, 220, 60)
    gc:drawString("YOU DIED. Enter to retry.", 20, H / 2, "top")
  end
end

local function snakeKey(key)
  if snake.dead then return end
  if key == "up" and snake.dir.y == 0 then snake.nextDir = { x = 0, y = -1 }
  elseif key == "down" and snake.dir.y == 0 then snake.nextDir = { x = 0, y = 1 }
  elseif key == "left" and snake.dir.x == 0 then snake.nextDir = { x = -1, y = 0 }
  elseif key == "right" and snake.dir.x == 0 then snake.nextDir = { x = 1, y = 0 }
  end
end

local function snakeEnter()
  if snake.dead then snakeInit(); snakePlaceFood() end
end

-- ============================================================
--  TETROID (simplified tetris-like)
-- ============================================================
local tet = {}

local PIECES = {
  { n = 4, color = {60,220,255},  cells = {{0,1},{1,1},{2,1},{3,1}} }, -- I
  { n = 4, color = {255,220,60},  cells = {{1,0},{2,0},{1,1},{2,1}} }, -- O
  { n = 4, color = {200,80,255},  cells = {{1,0},{0,1},{1,1},{2,1}} }, -- T
  { n = 4, color = {80,255,120},  cells = {{1,0},{2,0},{0,1},{1,1}} }, -- S
  { n = 4, color = {255,80,80},   cells = {{0,0},{1,0},{1,1},{2,1}} }, -- Z
  { n = 4, color = {80,120,255},  cells = {{0,0},{0,1},{1,1},{2,1}} }, -- J
  { n = 4, color = {255,150,60},  cells = {{2,0},{0,1},{1,1},{2,1}} }, -- L
}

local function tetNewGrid()
  local g = {}
  for r = 1, tet.rows do
    g[r] = {}
    for c = 1, tet.cols do g[r][c] = 0 end
  end
  return g
end

local function tetSpawn()
  local p = PIECES[math.random(1, #PIECES)]
  tet.pieceN = p.n
  tet.cells = {}
  for i, cell in ipairs(p.cells) do tet.cells[i] = { x = cell[1], y = cell[2] } end
  tet.color = p.color
  tet.px = math.floor(tet.cols / 2) - 2
  tet.py = 0
end

local function tetCollides(cells, px, py)
  for i = 1, #cells do
    local gx, gy = px + cells[i].x, py + cells[i].y
    if gx < 0 or gx >= tet.cols or gy >= tet.rows then return true end
    if gy >= 0 and tet.grid[gy + 1][gx + 1] ~= 0 then return true end
  end
  return false
end

local function tetInit()
  tet.cell = 9
  tet.cols = 10
  tet.rows = 18
  tet.offX = 4
  tet.offY = 20
  tet.grid = tetNewGrid()
  tet.score = 0
  tet.dead = false
  tet.frame = 0
  tet.speed = 12
  tetSpawn()
end

local function tetLockPiece()
  for i = 1, #tet.cells do
    local gx, gy = tet.px + tet.cells[i].x, tet.py + tet.cells[i].y
    if gy >= 0 then tet.grid[gy + 1][gx + 1] = tet.color end
  end
  -- clear full lines
  local cleared = 0
  local r = tet.rows
  while r >= 1 do
    local full = true
    for c = 1, tet.cols do
      if tet.grid[r][c] == 0 then full = false break end
    end
    if full then
      table.remove(tet.grid, r)
      table.insert(tet.grid, 1, {})
      for c = 1, tet.cols do tet.grid[1][c] = 0 end
      cleared = cleared + 1
    else
      r = r - 1
    end
  end
  if cleared > 0 then tet.score = tet.score + cleared * cleared * 100 end
  tetSpawn()
  if tetCollides(tet.cells, tet.px, tet.py) then tet.dead = true end
end

local function tetTick()
  if tet.dead then return end
  tet.frame = tet.frame + 1
  if tet.frame % tet.speed ~= 0 then return end
  if not tetCollides(tet.cells, tet.px, tet.py + 1) then
    tet.py = tet.py + 1
  else
    tetLockPiece()
  end
end

local function tetRotate()
  local n = tet.pieceN
  local newCells = {}
  for i = 1, #tet.cells do
    local c = tet.cells[i]
    newCells[i] = { x = n - 1 - c.y, y = c.x }
  end
  if not tetCollides(newCells, tet.px, tet.py) then tet.cells = newCells end
end

local function tetPaint(gc)
  setColor(gc, 12, 12, 22)
  gc:fillRect(0, 0, W, H)

  setColor(gc, 60, 60, 70)
  gc:drawRect(tet.offX - 1, tet.offY - 1, tet.cols * tet.cell + 1, tet.rows * tet.cell + 1)

  for r = 1, tet.rows do
    for c = 1, tet.cols do
      local v = tet.grid[r][c]
      if v ~= 0 then
        setColor(gc, v[1], v[2], v[3])
        gc:fillRect(tet.offX + (c-1)*tet.cell, tet.offY + (r-1)*tet.cell, tet.cell-1, tet.cell-1)
      end
    end
  end

  setColor(gc, tet.color[1], tet.color[2], tet.color[3])
  for i = 1, #tet.cells do
    local gx, gy = tet.px + tet.cells[i].x, tet.py + tet.cells[i].y
    if gy >= 0 then
      gc:fillRect(tet.offX + gx*tet.cell, tet.offY + gy*tet.cell, tet.cell-1, tet.cell-1)
    end
  end

  setColor(gc, 255, 255, 255)
  gc:drawString("Score: " .. tet.score, tet.offX + tet.cols*tet.cell + 10, tet.offY, "top")
  gc:drawString("esc = menu", 4, 2, "top")

  if tet.dead then
    setColor(gc, 255, 220, 60)
    gc:drawString("TOPPED OUT.", tet.offX + tet.cols*tet.cell + 10, tet.offY + 30, "top")
    gc:drawString("Enter to retry.", tet.offX + tet.cols*tet.cell + 10, tet.offY + 50, "top")
  end
end

local function tetKey(key)
  if tet.dead then return end
  if key == "left" then
    if not tetCollides(tet.cells, tet.px - 1, tet.py) then tet.px = tet.px - 1 end
  elseif key == "right" then
    if not tetCollides(tet.cells, tet.px + 1, tet.py) then tet.px = tet.px + 1 end
  elseif key == "down" then
    if not tetCollides(tet.cells, tet.px, tet.py + 1) then tet.py = tet.py + 1 end
  elseif key == "up" then
    tetRotate()
  end
end

local function tetEnter()
  if tet.dead then tetInit() end
end

-- ============================================================
--  GEO RUSH (endless-runner / geometry-dash-like)
-- ============================================================
local geo = {}

local function geoInit()
  geo.groundY = H - 24
  geo.player = { x = 30, y = geo.groundY - 14, w = 14, h = 14, vy = 0, onGround = true }
  geo.gravity = 1.0
  geo.jumpV = -9.5
  geo.scroll = 4
  geo.obstacles = {}
  geo.dist = 0
  geo.dead = false
  geo.spawnTimer = 40
end

local function geoSpawnObstacle()
  local h = math.random(12, 26)
  table.insert(geo.obstacles, { x = W + 10, y = geo.groundY - h, w = 12, h = h })
end

local function geoAABB(a, b)
  return a.x < b.x + b.w and a.x + a.w > b.x and a.y < b.y + b.h and a.y + a.h > b.y
end

local function geoTick()
  if geo.dead then return end
  geo.dist = geo.dist + 1

  local p = geo.player
  p.vy = p.vy + geo.gravity
  p.y = p.y + p.vy
  if p.y >= geo.groundY - p.h then
    p.y = geo.groundY - p.h
    p.vy = 0
    p.onGround = true
  else
    p.onGround = false
  end

  geo.spawnTimer = geo.spawnTimer - 1
  if geo.spawnTimer <= 0 then
    geoSpawnObstacle()
    geo.spawnTimer = math.random(35, 65)
  end

  for i = #geo.obstacles, 1, -1 do
    local o = geo.obstacles[i]
    o.x = o.x - geo.scroll
    if o.x + o.w < 0 then
      table.remove(geo.obstacles, i)
    elseif geoAABB(p, o) then
      geo.dead = true
    end
  end

  if geo.dist % 400 == 0 and geo.scroll < 9 then geo.scroll = geo.scroll + 0.5 end
end

local function geoJump()
  if geo.dead then return end
  if geo.player.onGround then
    geo.player.vy = geo.jumpV
    geo.player.onGround = false
  end
end

local function geoPaint(gc)
  setColor(gc, 15, 15, 28)
  gc:fillRect(0, 0, W, H)

  setColor(gc, 90, 90, 110)
  gc:fillRect(0, geo.groundY, W, H - geo.groundY)

  setColor(gc, 255, 100, 100)
  for i = 1, #geo.obstacles do
    local o = geo.obstacles[i]
    gc:fillRect(o.x, o.y, o.w, o.h)
  end

  setColor(gc, 60, 255, 200)
  gc:fillRect(geo.player.x, geo.player.y, geo.player.w, geo.player.h)

  setColor(gc, 255, 255, 255)
  gc:drawString("Dist: " .. geo.dist, 4, 2, "top")
  gc:drawString("esc = menu", W - 90, 2, "top")

  if geo.dead then
    setColor(gc, 255, 220, 60)
    gc:drawString("SPLAT. Enter to retry.", 20, H / 2, "top")
  end
end

local function geoEnter()
  if geo.dead then geoInit() end
end

-- ============================================================
--  MENU
-- ============================================================
local function menuPaint(gc)
  setColor(gc, 10, 10, 20)
  gc:fillRect(0, 0, W, H)

  setColor(gc, 255, 255, 255)
  gc:drawString("NSPIRE GAME HUB", W/2 - 70, 14, "top")
  setColor(gc, 150, 150, 160)
  gc:drawString("up/down + enter to pick", W/2 - 90, 32, "top")

  for i = 1, #menuItems do
    local y = 60 + (i-1) * 30
    if i == menuIndex then
      setColor(gc, 60, 255, 120)
      gc:fillRect(W/2 - 90, y - 4, 180, 24)
      setColor(gc, 10, 10, 20)
    else
      setColor(gc, 220, 220, 230)
    end
    gc:drawString(menuItems[i], W/2 - 80, y, "top")
  end
end

local function menuKey(key)
  if key == "up" then
    menuIndex = menuIndex - 1
    if menuIndex < 1 then menuIndex = #menuItems end
  elseif key == "down" then
    menuIndex = menuIndex + 1
    if menuIndex > #menuItems then menuIndex = 1 end
  end
end

local function menuEnter()
  local pick = menuItems[menuIndex]
  if pick == "Snek Classic" then
    snakeInit(); snakePlaceFood(); state = "snake"
  elseif pick == "Tetroid" then
    tetInit(); state = "tetroid"
  elseif pick == "Geo Rush" then
    geoInit(); state = "georush"
  end
end

-- ============================================================
--  GLOBAL DISPATCH
-- ============================================================
function on.construction()
  local ok, ms = pcall(function() return timer.getMilliSecCounter() end)
  math.randomseed(ok and ms or 42)
end

function on.resize()
  W = platform.window:width()
  H = platform.window:height()
  platform.window:invalidate()
end

function on.paint(gc)
  if state == "menu" then menuPaint(gc)
  elseif state == "snake" then snakePaint(gc)
  elseif state == "tetroid" then tetPaint(gc)
  elseif state == "georush" then geoPaint(gc)
  end
end

function on.timer()
  if state == "snake" then snakeTick()
  elseif state == "tetroid" then tetTick()
  elseif state == "georush" then geoTick()
  end
  platform.window:invalidate()
end

function on.arrowKey(key)
  if state == "menu" then menuKey(key)
  elseif state == "snake" then snakeKey(key)
  elseif state == "tetroid" then tetKey(key)
  end
  platform.window:invalidate()
end

function on.enterKey()
  if state == "menu" then menuEnter()
  elseif state == "snake" then snakeEnter()
  elseif state == "tetroid" then tetEnter()
  elseif state == "georush" then geoEnter()
  end
  platform.window:invalidate()
end

-- space bar also jumps in Geo Rush, because mashing enter mid-sprint is a pain
function on.charIn(ch)
  if state == "georush" and ch == " " then geoJump() end
end

function on.escapeKey()
  state = "menu"
  platform.window:invalidate()
end

function on.tabKey()
  if state == "georush" then geoJump() end
end

timer.start(0.05) -- ~20 fps global tick, each game throttles its own speed off this
