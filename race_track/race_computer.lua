-- =========================
-- RACE COMPUTER: startup
-- =========================

-- --------- CONFIG ---------
local MODE_BUTTON_SIDE  = "left"
local START_BUTTON_SIDE = "right"
local RESET_BUTTON_SIDE = "back"
local LAP_SELECTOR_SIDE = "top"
local MODEM_SIDE        = "bottom"

-- Set these to sides or peripheral names from `peripherals`
local START_MONITOR_NAME    = "monitor_20"
local BEST_MONITOR_NAME     = "monitor_17"
local MODE_MONITOR_NAME     = "monitor_18"
local SESSION_MONITOR_NAME  = "monitor_21"

local PROTOCOL = "race_net_v1"
local RECORD_FILE = "central_records.lua"
-- --------------------------

if not rednet.isOpen(MODEM_SIDE) then
  rednet.open(MODEM_SIDE)
end

local startMon = peripheral.wrap(START_MONITOR_NAME)
local bestMon = peripheral.wrap(BEST_MONITOR_NAME)
local modeMon = peripheral.wrap(MODE_MONITOR_NAME)
local sessionMon = peripheral.wrap(SESSION_MONITOR_NAME)


local function resetMonitorPalette(mon)
  local defaults = {
    [colors.white]     = 0xF0F0F0,
    [colors.orange]    = 0xF2B233,
    [colors.magenta]   = 0xE57FD8,
    [colors.lightBlue] = 0x99B2F2,
    [colors.yellow]    = 0xDEDE6C,
    [colors.lime]      = 0x7FCC19,
    [colors.pink]      = 0xF2B2CC,
    [colors.gray]      = 0x4C4C4C,
    [colors.lightGray] = 0x999999,
    [colors.cyan]      = 0x4C99B2,
    [colors.purple]    = 0xB266E5,
    [colors.blue]      = 0x3366CC,
    [colors.brown]     = 0x7F664C,
    [colors.green]     = 0x57A64E,
    [colors.red]       = 0xCC4C4C,
    [colors.black]     = 0x111111
  }

  for col, hex in pairs(defaults) do
    local r, g, b = colors.unpackRGB(hex)
    mon.setPaletteColor(col, r, g, b)
  end
end

resetMonitorPalette(startMon)
resetMonitorPalette(bestMon)
resetMonitorPalette(modeMon)
resetMonitorPalette(sessionMon)

if not startMon then error("Could not wrap start monitor") end
if not bestMon then error("Could not wrap best-times monitor") end
if not modeMon then error("Could not wrap mode monitor") end
if not sessionMon then error("Could not wrap session monitor") end

startMon.setTextScale(0.5)
bestMon.setTextScale(1)
modeMon.setTextScale(1)
sessionMon.setTextScale(2)

local bigFont = {
  ["0"] = {"111","101","101","101","111"},
  ["1"] = {"010","110","010","010","111"},
  ["2"] = {"111","001","111","100","111"},
  ["3"] = {"111","001","111","001","111"},
  ["4"] = {"101","101","111","001","001"},
  ["5"] = {"111","100","111","001","111"},
  ["6"] = {"111","100","111","101","111"},
  ["7"] = {"111","001","001","001","001"},
  ["8"] = {"111","101","111","101","111"},
  ["9"] = {"111","101","111","001","111"},
  ["."] = {"0","0","0","0","1"},
  [":"] = {"0","1","0","1","0"},
  [" "] = {"0","0","0","0","0"},
  ["T"] = {"111","010","010","010","010"},
  ["I"] = {"111","010","010","010","111"},
  ["M"] = {"101","111","111","101","101"},
  ["E"] = {"111","100","110","100","111"},
  ["F"] = {"111","100","110","100","100"},
  ["H"] = {"101","101","111","101","101"},
  ["N"] = {"101","111","111","111","101"},
  ["S"] = {"111","100","111","001","111"},
  ["A"] = {"010","101","111","101","101"},
  ["B"] = {"110","101","110","101","110"},
  ["G"] = {"111","100","101","101","111"},
  ["K"] = {"101","110","100","110","101"},
  ["L"] = {"100","100","100","100","111"},
  ["R"] = {"110","101","110","101","101"},
  ["C"] = {"111","100","100","100","111"},
}

local function loadRecords()
  if fs.exists(RECORD_FILE) then
    local h = fs.open(RECORD_FILE, "r")
    local txt = h.readAll()
    h.close()
    local data = textutils.unserialize(txt)
    if type(data) == "table" then return data end
  end
  return {}
end

local function saveRecords(data)
  local h = fs.open(RECORD_FILE, "w")
  h.write(textutils.serialize(data))
  h.close()
end

local records = loadRecords()

local mode = "race"         -- "race" or "time_trial"
local phase = "idle"        -- idle, countdown, running, finished
local currentLapTarget = nil
local countdownEndsAt = nil
local countdownLastShown = nil
local ttPlayer = nil
local raceStartEpoch = nil

local players = {}

local lastInputs = {
  modeBtn = redstone.getInput(MODE_BUTTON_SIDE),
  startBtn = redstone.getInput(START_BUTTON_SIDE),
  resetBtn = redstone.getInput(RESET_BUTTON_SIDE),
}

local function ensurePlayer(name)
  if not players[name] then
    players[name] = {
      connected = false,
      enabled = false,
      armed = false,
      active = false,
      finished = false,
      dnf = false,

      lapsCompleted = 0,
      lastLap = nil,
      bestLapSession = nil,
      allTimeBest = records[name],
      totalTime = nil,
      finalTime = nil,
      sessionLaps = {},
      mode = mode,
    }
  end
  return players[name]
end

local function nowMs()
  return os.epoch("utc")
end

local function fmtTime(t)
  if not t then return "--.--" end
  return string.format("%.2f", t)
end

local function lapSelectorValue()
  return redstone.getAnalogInput(LAP_SELECTOR_SIDE) + 1
end

local function send(msg)
  rednet.broadcast(msg, PROTOCOL)
end

local function sendTo(playerName, msg)
  msg.target = playerName
  rednet.broadcast(msg, PROTOCOL)
end

local function sessionParticipants()
  local list = {}
  for name, p in pairs(players) do
    if p.armed or p.active or p.finished or p.dnf then
      table.insert(list, name)
    end
  end
  table.sort(list)
  return list
end

local function clearSessionFields()
  for _, p in pairs(players) do
    p.armed = false
    p.active = false
    p.finished = false
    p.dnf = false
    p.lapsCompleted = 0
    p.lastLap = nil
    p.bestLapSession = nil
    p.totalTime = nil
    p.finalTime = nil
    p.sessionLaps = {}
  end
  ttPlayer = nil
end

local function resetAll()
  phase = "idle"
  countdownEndsAt = nil
  countdownLastShown = nil
  currentLapTarget = nil
  raceStartEpoch = nil
  clearSessionFields()
  send({ type = "reset_lane", target = "*" })
end

local function recordBest(playerName, maybeBest)
  if maybeBest and (not records[playerName] or maybeBest < records[playerName]) then
    records[playerName] = maybeBest
    saveRecords(records)
  end
  ensurePlayer(playerName).allTimeBest = records[playerName]
end

-- =========================
-- START MONITOR DRAWING
-- =========================

local function clearMonitor(mon, bg)
  local prev = term.current()
  term.redirect(mon)
  term.setBackgroundColor(bg or colors.black)
  term.clear()
  term.setCursorPos(1, 1)
  term.redirect(prev)
end

local function charWidth(ch)
  local patt = bigFont[ch] or bigFont[" "]
  return #patt[1]
end

local function stringUnitsWide(str)
  local total = 0
  for i = 1, #str do
    local ch = str:sub(i, i)
    total = total + charWidth(ch)
    if i < #str then
      total = total + 1
    end
  end
  return total
end

local function drawPixelSafe(px, py, colour)
  local w, h = term.getSize()
  if px >= 1 and px <= w and py >= 1 and py <= h then
    paintutils.drawPixel(px, py, colour)
  end
end

local function drawCharScaled(ch, px, py, scale, colour)
  local patt = bigFont[ch] or bigFont[" "]
  local pw = #patt[1]

  for row = 1, 5 do
    local line = patt[row]
    for col = 1, pw do
      if line:sub(col, col) == "1" then
        local bx = px + (col - 1) * scale
        local by = py + (row - 1) * scale

        for sy = 0, scale - 1 do
          for sx = 0, scale - 1 do
            drawPixelSafe(bx + sx, by + sy, colour)
          end
        end
      end
    end
  end
end

local function drawStringScaled(mon, str, px, py, scale, colour)
  local prev = term.current()
  term.redirect(mon)

  for i = 1, #str do
    local ch = str:sub(i, i)
    drawCharScaled(ch, px, py, scale, colour)
    px = px + charWidth(ch) * scale
    if i < #str then
      px = px + scale
    end
  end

  term.redirect(prev)
end

local function getStringScale(mon, str, maxWidthPadding, maxHeightPadding)
  local prev = term.current()
  term.redirect(mon)

  local w, h = term.getSize()
  local totalUnitsWide = stringUnitsWide(str)
  local totalUnitsHigh = 5

  local scaleX = math.max(1, math.floor((w - (maxWidthPadding or 2)) / totalUnitsWide))
  local scaleY = math.max(1, math.floor((h - (maxHeightPadding or 2)) / totalUnitsHigh))

  term.redirect(prev)
  return math.max(1, math.min(scaleX, scaleY))
end

local function getDefaultRGB(col)
  local defaults = {
    [colors.white]     = 0xF0F0F0,
    [colors.orange]    = 0xF2B233,
    [colors.magenta]   = 0xE57FD8,
    [colors.lightBlue] = 0x99B2F2,
    [colors.yellow]    = 0xDEDE6C,
    [colors.lime]      = 0x7FCC19,
    [colors.pink]      = 0xF2B2CC,
    [colors.gray]      = 0x4C4C4C,
    [colors.lightGray] = 0x999999,
    [colors.cyan]      = 0x4C99B2,
    [colors.purple]    = 0xB266E5,
    [colors.blue]      = 0x3366CC,
    [colors.brown]     = 0x7F664C,
    [colors.green]     = 0x57A64E,
    [colors.red]       = 0xCC4C4C,
    [colors.black]     = 0x111111
  }

  local rgb = defaults[col] or 0x000000
  return colors.unpackRGB(rgb)
end

local function clamp01(x)
  if x < 0 then return 0 end
  if x > 1 then return 1 end
  return x
end

local function setPaletteFromColour(mon, paletteSlot, baseColour, factor)
  local r, g, b = getDefaultRGB(baseColour)
  r = clamp01(r * factor)
  g = clamp01(g * factor)
  b = clamp01(b * factor)
  mon.setPaletteColor(paletteSlot, r, g, b)
  return paletteSlot
end

local function setPaletteFromRGB(mon, paletteSlot, hex)
  local r, g, b = colors.unpackRGB(hex)
  mon.setPaletteColor(paletteSlot, r, g, b)
  return paletteSlot
end

local function fmtBoardTime(t)
  if not t then return "--:--.--" end

  local totalHundredths = math.floor(t * 100 + 0.5)
  local hours = math.floor(totalHundredths / 360000)
  local minutes = math.floor((totalHundredths % 360000) / 6000)
  local secs = math.floor((totalHundredths % 6000) / 100)
  local hundredths = totalHundredths % 100

  if hours > 0 then
    return string.format("%d:%02d:%02d", hours, minutes, secs)
  else
    return string.format("%02d:%02d.%02d", minutes, secs, hundredths)
  end
end

local function drawShadowedStringScaled(mon, str, px, py, scale, mainColour, shadowColour)
  drawStringScaled(mon, str, px + scale, py + scale, scale, shadowColour)
  drawStringScaled(mon, str, px, py, scale, mainColour)
end

local function drawModeHeader()
  local title = "MINE KART"

  local prev = term.current()
  term.redirect(modeMon)
  local w, h = term.getSize()
  term.redirect(prev)

  local titleScale = 1
  local titleWidth = stringUnitsWide(title) * titleScale
  local titleHeight = 5 * titleScale

  local titleX = math.floor((w - titleWidth) / 2) + 1
  local titleY = 2

  local darkYellowShadow = setPaletteFromColour(modeMon, colors.gray, colors.yellow, 0.38)
  drawShadowedStringScaled(modeMon, title, titleX, titleY, titleScale, colors.yellow, darkYellowShadow)

  return titleY + titleHeight + 2
end

local function drawSessionHeader()
  local title = (mode == "race") and "RACE" or "TT MODE"

  local prev = term.current()
  term.redirect(sessionMon)
  local w, h = term.getSize()
  term.redirect(prev)

  local titleScale = 1
  local titleWidth = stringUnitsWide(title) * titleScale
  local titleHeight = 5 * titleScale

  local titleX = math.floor((w - titleWidth) / 2) + 1
  local titleY = 2

  local darkYellowShadow = setPaletteFromColour(sessionMon, colors.gray, colors.yellow, 0.38)
  drawShadowedStringScaled(sessionMon, title, titleX, titleY, titleScale, colors.yellow, darkYellowShadow)

  return titleY + titleHeight + 2
end

local function drawBestHeader()
  local title = "BEST TIMES"
  local subtitle = "ALL-TIME RANKING"

  local prev = term.current()
  term.redirect(bestMon)
  local w, h = term.getSize()
  term.redirect(prev)

  local titleScale = 1
  local titleWidth = stringUnitsWide(title) * titleScale
  local titleHeight = 5 * titleScale

  while titleScale > 1 and titleWidth > (w - 2) do
    titleScale = titleScale - 1
    titleWidth = stringUnitsWide(title) * titleScale
    titleHeight = 5 * titleScale
  end

  local titleX = math.floor((w - titleWidth) / 2) + 1
  local titleY = 2

  local darkYellowShadow = setPaletteFromColour(bestMon, colors.gray, colors.yellow, 0.38)
  drawShadowedStringScaled(bestMon, title, titleX, titleY, titleScale, colors.yellow, darkYellowShadow)

  local subtitleY = titleY + titleHeight + 2
  bestMon.setCursorPos(math.max(1, math.floor((w - #subtitle) / 2) + 1), subtitleY)
  bestMon.setTextColor(colors.white)
  bestMon.setBackgroundColor(colors.black)
  bestMon.write(subtitle)

  return subtitleY + 2
end

local function drawFilledEllipse(mon, cx, cy, rx, ry, colour)
  local prev = term.current()
  term.redirect(mon)

  for dy = -ry, ry do
    for dx = -rx, rx do
      local nx = dx / rx
      local ny = dy / ry
      if (nx * nx + ny * ny) <= 1 then
        paintutils.drawPixel(cx + dx, cy + dy, colour)
      end
    end
  end

  term.redirect(prev)
end

local function drawStartLights(litPairs, goGreen)
  clearMonitor(startMon, colors.black)

  local prev = term.current()
  term.redirect(startMon)

  local w, h = term.getSize()

  local radius = 4
  local rx = radius * 1.5
  local ry = radius
  local cols = 5
  local colSpacing = rx * 2 + 3
  local rowSpacing = ry * 2 + 2

  local totalWidth = (cols - 1) * colSpacing
  local startX = math.floor((w - totalWidth) / 2)
  local topY = math.floor(h / 2) - math.floor(rowSpacing / 2)
  local bottomY = topY + rowSpacing

  local darkRed = colors.brown
  local brightRed = colors.red
  local green = colors.lime

  for i = 1, cols do
    local colour
    if goGreen then
      colour = green
    elseif i <= litPairs then
      colour = brightRed
    else
      colour = darkRed
    end

    local x = startX + (i - 1) * colSpacing
    drawFilledEllipse(startMon, x, topY, rx, ry, colour)
    drawFilledEllipse(startMon, x, bottomY, rx, ry, colour)
  end

  term.redirect(prev)
end

local function drawRunningTime(seconds)
  clearMonitor(startMon, colors.black)
  startMon.setTextScale(0.5)

  local prev = term.current()
  term.redirect(startMon)

  local w, h = term.getSize()

  -- Format time as MM:SS.hh
  local totalHundredths = math.floor(seconds * 100 + 0.5)

  local hours = math.floor(totalHundredths / 360000)
  local minutes = math.floor((totalHundredths % 360000) / 6000)
  local secs = math.floor((totalHundredths % 6000) / 100)
  local hundredths = totalHundredths % 100

  local timeStr

  if hours > 0 then
  -- H:MM:SS
  timeStr = string.format("%d:%02d:%02d", hours, minutes, secs)
  else
  -- MM:SS.hh
  timeStr = string.format("%02d:%02d.%02d", minutes, secs, hundredths)
  end

  local scale = getStringScale(startMon, timeStr, 4, 4)

  local textWidth = stringUnitsWide(timeStr) * scale
  local textHeight = 5 * scale

  local startX = math.floor((w - textWidth) / 2) + 1
  local startY = math.floor((h - textHeight) / 2) + 1

  drawStringScaled(startMon, timeStr, startX, startY, scale, colors.white)

  term.redirect(prev)
end

local function drawStartIdle()
  drawStartLights(0, false)
end

local function drawStartFinished()
  clearMonitor(startMon, colors.black)
  startMon.setTextScale(0.5)

  local prev = term.current()
  term.redirect(startMon)

  local w, h = term.getSize()
  term.redirect(prev)

  local text = "FINISH"
  local scale = getStringScale(startMon, text, 4, 2)

  local textWidth = stringUnitsWide(text) * scale
  local textHeight = 5 * scale

  local startX = math.floor((w - textWidth) / 2) + 1
  local startY = math.floor((h - textHeight) / 2) + 1

  drawStringScaled(startMon, text, startX, startY, scale, colors.yellow)
end

-- =========================
-- OTHER MONITORS
-- =========================

local function drawBestMonitor()
  bestMon.setBackgroundColor(colors.black)
  bestMon.clear()

  local w, h = bestMon.getSize()

  local function line(y, text, color)
    if y < 1 or y > h then return end
    bestMon.setCursorPos(1, y)
    bestMon.setTextColor(color or colors.white)
    bestMon.setBackgroundColor(colors.black)
    bestMon.write(text:sub(1, w))
  end

  local y = drawBestHeader()

    -- Table margins and column layout
  local leftPad = 2
  local rightPad = 2

  local posWidth = 5
  local bestWidth = 10
  local innerWidth = math.max(10, w - leftPad - rightPad)
  local nameWidth = math.max(6, innerWidth - posWidth - bestWidth - 2)

  local function tableLine(yPos, text, color)
    line(yPos, string.rep(" ", leftPad) .. text, color)
  end

  local header = string.format(
    "%-" .. posWidth .. "s %-" .. nameWidth .. "s %" .. bestWidth .. "s",
    "POS", "NAME", "BEST"
  )
  tableLine(y, header, colors.cyan)
  y = y + 1
  tableLine(y, string.rep("-", math.min(innerWidth, posWidth + nameWidth + bestWidth + 2)), colors.white)
  y = y + 1

  local ranked = {}
  local noTime = {}

  for name, p in pairs(players) do
    local best = records[name] or p.allTimeBest
    if best then
      table.insert(ranked, { name = name, best = best })
    else
      table.insert(noTime, { name = name })
    end
  end

  table.sort(ranked, function(a, b)
    if a.best == b.best then
      return a.name < b.name
    end
    return a.best < b.best
  end)

  table.sort(noTime, function(a, b)
    return a.name < b.name
  end)

  -- Ranked entries
  for i, e in ipairs(ranked) do
    if y > h then return end

    local colour = colors.white
    if i == 1 then
      -- gold
      colour = setPaletteFromRGB(bestMon, colors.brown, 0xD4AF37)
    elseif i == 2 then
      -- silver
      colour = setPaletteFromRGB(bestMon, colors.lightGray, 0xC0C0C0)
    elseif i == 3 then
      -- bronze
      colour = setPaletteFromRGB(bestMon, colors.orange, 0xCD7F32)
    end

    local row = string.format(
      "%-" .. posWidth .. "d %-" .. nameWidth .. "s %" .. bestWidth .. "s",
      i,
      e.name:sub(1, nameWidth),
      fmtBoardTime(e.best)
    )

    tableLine(y, row, colour)
    y = y + 1
  end

  -- Spacer before no-time section
  if #noTime > 0 and y <= h - 2 then
    y = y + 1
    tableLine(y, "NO RECORDED TIME", colors.red)
    y = y + 1
  end

  for _, e in ipairs(noTime) do
    if y > h then return end

    local row = string.format(
      "%-" .. posWidth .. "s %-" .. nameWidth .. "s %" .. bestWidth .. "s",
      "-",
      e.name:sub(1, nameWidth),
      "--:--.--"
    )

    tableLine(y, row, colors.gray)
    y = y + 1
  end
end

local function drawModeMonitor()
  modeMon.setBackgroundColor(colors.black)
  modeMon.clear()

  local w, h = modeMon.getSize()
  local leftPad = 2

  local function line(y, text, color)
    if y < 1 or y > h then return end
    modeMon.setCursorPos(leftPad, y)
    modeMon.setTextColor(color or colors.white)
    modeMon.setBackgroundColor(colors.black)
    modeMon.write(text:sub(1, math.max(0, w - leftPad + 1)))
  end

  local y = drawModeHeader()

  line(y, "Welcome to Mine Kart! Select racing", colors.white)
  y = y + 1
  line(y, "mode with the toggle on the right.", colors.white)
  y = y + 2

  local modeText = (mode == "race") and "RACE" or "TIME TRIAL"
  local statusText = string.upper(phase)
  line(y, "Mode: " .. modeText .. "   Status: " .. statusText, colors.cyan)
  y = y + 2

  -- Count ready players
  local readyCount = 0
  for _, p in pairs(players) do
    if p.enabled then
      readyCount = readyCount + 1
    end
  end

  if mode == "race" then
    local laps = currentLapTarget or lapSelectorValue()
    line(y, "Race mode:", colors.orange)
    y = y + 1
    line(y, "Laps: " .. tostring(laps) .. " (change with lever on right)", colors.lightGray)
    y = y + 1
    line(y, "All ready players race together.", colors.white)
    y = y + 1
    line(y, "To ready, flick the lever in your pit.", colors.white)
    y = y + 1
    line(y, "To start, press the button next to", colors.white)
    y = y + 1
    line(y, "pole position on the track.", colors.white)
    y = y + 1
    line(y, "Toggle ready during race = DNF", colors.white)
    y = y + 2
  else
    line(y, "Time trial mode:", colors.orange)
    y = y + 1

    local readyColour = (readyCount > 1) and colors.red or colors.lime
    line(y, "One player is ready.", readyColour)
    y = y + 1

    line(y, "To ready, flick the lever in your pit.", colors.white)
    y = y + 1
    line(y, "To start, press the button next to", colors.white)
    y = y + 1
    line(y, "pole position on the track.", colors.white)
    y = y + 1
    line(y, "Reset ends the current session.", colors.white)
    y = y + 2
  end

  line(y, "Players:", colors.orange)
  y = y + 1

  local names = {}
  for name, _ in pairs(players) do
    table.insert(names, name)
  end
  table.sort(names)

  for _, name in ipairs(names) do
    if y > h then break end
    local p = players[name]
    local ready = p.enabled and "READY" or "NOT READY"
    local colour = p.enabled and colors.lime or colors.red
    line(y, string.format("%-12s %s", name:sub(1, 12), ready), colour)
    y = y + 1
  end

end

local function raceSortKey(a, b)
  local pa, pb = players[a], players[b]

  local function rank(p)
    if p.finished then return 1 end
    if p.active or p.armed then return 2 end
    if p.dnf then return 3 end
    return 4
  end

  local ra, rb = rank(pa), rank(pb)
  if ra ~= rb then return ra < rb end

  if pa.finished and pb.finished then
    return (pa.finalTime or 1e18) < (pb.finalTime or 1e18)
  end

  if (pa.active or pa.armed) and (pb.active or pb.armed) then
    if pa.lapsCompleted ~= pb.lapsCompleted then
      return pa.lapsCompleted > pb.lapsCompleted
    end
    return (pa.bestLapSession or 1e18) < (pb.bestLapSession or 1e18)
  end

  if pa.dnf and pb.dnf then
    return pa.lapsCompleted > pb.lapsCompleted
  end

  return a < b
end

local function drawSessionMonitor()
  sessionMon.setBackgroundColor(colors.black)
  sessionMon.clear()

  local w, h = sessionMon.getSize()
  local leftPad = 2

  local function line(y, text, color)
    if y < 1 or y > h then return end
    sessionMon.setCursorPos(leftPad, y)
    sessionMon.setTextColor(color or colors.white)
    sessionMon.setBackgroundColor(colors.black)
    sessionMon.write(text:sub(1, math.max(0, w - leftPad + 1)))
  end

  local y = drawSessionHeader()

  local statusText = string.upper(phase)

  if mode == "race" then
    local laps = currentLapTarget or lapSelectorValue()

    local statusLabel = statusText
    local lapsLabel = "Laps: " .. tostring(laps)

    sessionMon.setBackgroundColor(colors.black)

    -- left-aligned status
    sessionMon.setCursorPos(leftPad, y)
    sessionMon.setTextColor(colors.cyan)
    sessionMon.write(statusLabel)

    -- right-aligned laps
    sessionMon.setCursorPos(w - #lapsLabel - leftPad+2, y)
    sessionMon.setTextColor(colors.orange)
    sessionMon.write(lapsLabel)

    y = y + 1

    local leftPad = 1

    local posWidth = 2
    local nameWidth = 7
    local lapsWidth = 3
    local timeWidth = 8

    local function line(yPos, text, color)
      if yPos < 1 or yPos > h then return end
      sessionMon.setCursorPos(leftPad, yPos)
      sessionMon.setTextColor(color or colors.white)
      sessionMon.setBackgroundColor(colors.black)
      sessionMon.write(text:sub(1, 25 - leftPad))
    end

    local header = string.format(
    " " .. "%-" .. posWidth .. "s %-" .. nameWidth .. "s %-" .. lapsWidth .. "s %" .. timeWidth .. "s",
    "PL", "NAME", "LAP", "TIME"
    )
    line(y, header, colors.lightBlue)
    y = y + 1

    line(y, " " ..string.rep("-", 23), colors.white)
    y = y + 1

    local names = {}

    if phase == "idle" then
      for name, p in pairs(players) do
        if p.enabled then
          table.insert(names, name)
        end
      end

      table.sort(names, function(a, b)
        local pa, pb = players[a], players[b]
        local ba = pa.allTimeBest or records[a]
        local bb = pb.allTimeBest or records[b]

        if ba == nil and bb == nil then return a < b end
        if ba == nil then return false end
        if bb == nil then return true end
        return ba < bb
      end)
    else
      names = sessionParticipants()
      table.sort(names, raceSortKey)
    end

    for i, name in ipairs(names) do
      if y > h then break end
      local p = players[name]

      local timeCol = "--:--.--"
      local rowColour = colors.white

      if phase == "idle" then
        displayPlace = "-"

        rowColour = colors.white
      else
        if p.finished then
          timeCol = fmtBoardTime(p.finalTime)
          rowColour = colors.lime
        elseif p.dnf then
          timeCol = "DNF"
          rowColour = colors.red
        elseif p.active or p.armed then
          if p.totalTime then
            timeCol = fmtBoardTime(p.totalTime)
          else
            timeCol = "--:--.--"
          end
        end
      end

      local currentLap
      if phase == "idle" then
        currentLap = 0
      else
        currentLap = math.min((p.lapsCompleted or 0) + 1, currentLapTarget or lapSelectorValue())
      end
      if p.finished then
        currentLap = currentLapTarget or lapSelectorValue()
      elseif p.dnf and (p.lapsCompleted or 0) > 0 then
        currentLap = (p.lapsCompleted or 0) + 1
      end

      local row = string.format(
        " %-" .. posWidth .. "d %-" .. nameWidth .. "s %-" .. lapsWidth .. "d %" .. timeWidth .. "s",
        i,
        name:sub(1, nameWidth),
        currentLap,
        timeCol
      )

      line(y, row, rowColour)
      y = y + 1
    end

  else
    line(y, "Status: " .. statusText, colors.cyan)
    y = y + 2
    if not ttPlayer then
      line(y, "No active player selected.", colors.red)
      y = y + 1
      line(y, "Ready exactly one player, then", colors.white)
      y = y + 1
      line(y, "press the button next to pole.", colors.white)
      return
    end

    local p = players[ttPlayer]

    line(y, "Player: " .. ttPlayer, colors.orange)
    y = y + 1
    line(y, "All-time best: " .. fmtBoardTime(p.allTimeBest), colors.lightBlue)
    y = y + 2

    line(y, "Session laps:", colors.orange)
    y = y + 1

    if #p.sessionLaps == 0 then
      line(y, "No laps recorded yet.", colors.gray)
      return
    end

    local lapNumWidth = 4
    local timeWidth = 10

    for i, lap in ipairs(p.sessionLaps) do
      if y > h then break end

      local colour = colors.white
      if p.allTimeBest and math.abs(lap - p.allTimeBest) < 0.0005 then
        colour = colors.lime
      end

      local row = string.format(
        "%-" .. lapNumWidth .. "d %" .. timeWidth .. "s",
        i,
        fmtBoardTime(lap)
      )

      line(y, row, colour)
      y = y + 1
    end
  end
end

local function redrawAll()
  drawBestMonitor()
  drawModeMonitor()
  drawSessionMonitor()

  if phase == "idle" then
    drawStartIdle()
  elseif phase == "finished" then
    drawStartFinished()
  elseif phase == "running" and raceStartEpoch then
    local elapsed = (nowMs() - raceStartEpoch) / 1000
    if elapsed >= 10 then
      drawRunningTime(elapsed)
    end
  end
end

local function markDNF(playerName)
  local p = ensurePlayer(playerName)
  if p.finished or p.dnf then return end
  p.dnf = true
  p.active = false
  p.armed = false
  sendTo(playerName, { type = "mark_dnf" })
  sendTo(playerName, { type = "disarm_lane" })
end

local function maybeEndRace()
  if mode ~= "race" or phase ~= "running" then return end

  local anyParticipants = false
  for _, p in pairs(players) do
    if p.finished or p.dnf or p.active or p.armed then
      anyParticipants = true
      if not p.finished and not p.dnf then
        return
      end
    end
  end

  if anyParticipants then
    phase = "finished"
    send({ type = "disarm_lane", target = "*" })
  end
end

local function startRaceSession()
  if phase ~= "idle" and phase ~= "finished" then return end

  clearSessionFields()
  currentLapTarget = lapSelectorValue()

  local any = false
  for name, p in pairs(players) do
    if p.enabled then
      any = true
      p.armed = true
      p.active = false
      p.mode = "race"
      sendTo(name, {
        type = "set_mode",
        mode = "race",
      })
      sendTo(name, {
        type = "arm_lane",
        mode = "race",
        lapTarget = currentLapTarget,
      })
      sendTo(name, {
        type = "prepare_start",
        mode = "race",
      })
    else
      sendTo(name, { type = "disarm_lane" })
    end
  end

  if any then
    mode = "race"
    phase = "countdown"
    countdownEndsAt = nowMs() + 5000
    countdownLastShown = nil
    raceStartEpoch = nil
  end
end

local function startTimeTrialSession()
  if phase ~= "idle" and phase ~= "finished" then return end

  clearSessionFields()

  local enabled = {}
  for name, p in pairs(players) do
    if p.enabled then table.insert(enabled, name) end
  end
  table.sort(enabled)

  if #enabled ~= 1 then
    ttPlayer = nil
    return
  end

  ttPlayer = enabled[1]
  local p = ensurePlayer(ttPlayer)
  p.armed = true
  p.mode = "time_trial"

  send({ type = "set_mode", target = "*", mode = "time_trial" })
  sendTo(ttPlayer, {
    type = "arm_lane",
    mode = "time_trial",
    lapTarget = 9999,
  })
  sendTo(ttPlayer, {
    type = "prepare_start",
    mode = "time_trial",
  })

  phase = "countdown"
  countdownEndsAt = nowMs() + 5000
  countdownLastShown = nil
  raceStartEpoch = nil
end

local function handleStartPressed()
  if mode == "race" then
    startRaceSession()
  else
    startTimeTrialSession()
  end
end

local function handleNetworkMessage(msg)
  if type(msg) ~= "table" or not msg.player then return end
  local p = ensurePlayer(msg.player)
  p.connected = true

  if msg.type == "hello" then
    p.enabled = msg.enabled or false
    recordBest(msg.player, msg.allTimeBest)

  elseif msg.type == "lane_status" then
    p.enabled = msg.enabled or false
    p.armed = msg.armed or false
    p.active = msg.active or false
    p.finished = msg.finished or false
    p.dnf = msg.dnf or false
    p.mode = msg.mode or p.mode
    p.lapsCompleted = msg.lapsCompleted or 0
    p.lastLap = msg.lastLap
    p.bestLapSession = msg.bestLapSession
    p.totalTime = msg.totalTime
    recordBest(msg.player, msg.allTimeBest)

  elseif msg.type == "toggle_changed" then
    p.enabled = msg.enabled or false

    if mode == "race" and (phase == "countdown" or phase == "running") then
      if p.armed or p.active then
        markDNF(msg.player)
        maybeEndRace()
      end
    elseif mode == "time_trial" and phase == "running" and ttPlayer == msg.player and not p.finished then
      p.active = false
      p.armed = false
      phase = "finished"
      sendTo(msg.player, { type = "disarm_lane" })
    end

  elseif msg.type == "checkpoint" then
    -- Optional debug hook

  elseif msg.type == "lap_complete" then
    p.lapsCompleted = msg.lap or p.lapsCompleted
    p.lastLap = msg.lapTime
    p.bestLapSession = msg.bestLapSession
    p.totalTime = msg.totalTime
    table.insert(p.sessionLaps, msg.lapTime)
    p.active = true
    recordBest(msg.player, msg.allTimeBest)

  elseif msg.type == "finished" then
    p.finished = true
    p.active = false
    p.armed = false
    p.finalTime = msg.finalTime
    p.bestLapSession = msg.bestLapSession
    recordBest(msg.player, msg.allTimeBest)
    sendTo(msg.player, { type = "disarm_lane" })
    maybeEndRace()
  end
end

local function redstoneLoop()
  while true do
    os.pullEvent("redstone")

    local modeNow = redstone.getInput(MODE_BUTTON_SIDE)
    local startNow = redstone.getInput(START_BUTTON_SIDE)
    local resetNow = redstone.getInput(RESET_BUTTON_SIDE)

    if modeNow and not lastInputs.modeBtn then
      if phase == "idle" or phase == "finished" then
        mode = (mode == "race") and "time_trial" or "race"
        send({ type = "set_mode", target = "*", mode = mode })
      end
    end

    if startNow and not lastInputs.startBtn then
      handleStartPressed()
    end

    if resetNow and not lastInputs.resetBtn then
      resetAll()
    end

    lastInputs.modeBtn = modeNow
    lastInputs.startBtn = startNow
    lastInputs.resetBtn = resetNow
  end
end

local function networkLoop()
  while true do
    local _, msg, protocol = rednet.receive(PROTOCOL)
    if protocol == PROTOCOL then
      handleNetworkMessage(msg)
    end
  end
end

local function countdownLoop()
  while true do
    if phase == "countdown" and countdownEndsAt then
      local remainingMs = countdownEndsAt - nowMs()

      if remainingMs > 0 then
        local totalMs = 5000
        local elapsedMs = totalMs - remainingMs
        local step = math.floor(elapsedMs / 1000) + 1
        if step < 0 then step = 0 end
        if step > 5 then step = 5 end

        if countdownLastShown ~= step then
          countdownLastShown = step
          drawStartLights(step, false)
        end
      else
        drawStartLights(5, true)
        phase = "running"
        local startEpoch = nowMs()
        raceStartEpoch = startEpoch

        if mode == "race" then
          for name, p in pairs(players) do
            if p.armed and p.enabled and not p.dnf then
              p.active = true
              sendTo(name, {
                type = "go",
                startEpoch = startEpoch,
              })
            end
          end
        else
          if ttPlayer then
            local p = players[ttPlayer]
            if p and p.armed and p.enabled then
              p.active = true
              sendTo(ttPlayer, {
                type = "go",
                startEpoch = startEpoch,
              })
            end
          end
        end

        countdownEndsAt = nil
        countdownLastShown = nil
        sleep(1)
      end
    end
    sleep(0.05)
  end
end

local function uiLoop()
  while true do
    redrawAll()
    sleep(0.2)
  end
end

resetAll()
redrawAll()
parallel.waitForAny(redstoneLoop, networkLoop, countdownLoop, uiLoop)