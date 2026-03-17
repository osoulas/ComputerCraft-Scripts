-- =========================
-- LANE COMPUTER: startup
-- =========================

-- --------- CONFIG ---------
local PLAYER_NAME = "Oskar"

local DETECTOR_START_SIDE = "left"   -- start/finish detector
local DETECTOR_MID_SIDE   = "right"  -- mid-track detector
local TOGGLE_SIDE         = "back"   -- participation toggle
local MODEM_SIDE          = "bottom"

-- Set this to a side ("top") or a peripheral name from `peripherals`
local MONITOR_NAME = "monitor_7"

local PROTOCOL = "race_net_v1"
local RECORD_FILE = "lane_record.lua"

local DETECTOR_DEBOUNCE_MS = 300
-- --------------------------

local function loadRecord()
  if fs.exists(RECORD_FILE) then
    local h = fs.open(RECORD_FILE, "r")
    local txt = h.readAll()
    h.close()
    local data = textutils.unserialize(txt)
    if type(data) == "table" then return data end
  end
  return {
    allTimeBest = nil,
    allTimeLapsCompleted = 0,
    previousLapAllSessions = nil,
  }
end

local function saveRecord(data)
  local h = fs.open(RECORD_FILE, "w")
  h.write(textutils.serialize(data))
  h.close()
end

local record = loadRecord()
record.allTimeLapsCompleted = record.allTimeLapsCompleted or 0
record.previousLapAllSessions = record.previousLapAllSessions or nil

if not rednet.isOpen(MODEM_SIDE) then
  rednet.open(MODEM_SIDE)
end

local mon = peripheral.wrap(MONITOR_NAME)
if not mon then
  error("Could not wrap monitor: " .. tostring(MONITOR_NAME))
end

mon.setTextScale(0.5)

local bigFont = {
  -- NUMBERS
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

  -- LETTERS
  ["A"] = {"010","101","111","101","101"},
  ["B"] = {"110","101","110","101","110"},
  ["C"] = {"111","100","100","100","111"},
  ["D"] = {"110","101","101","101","110"},
  ["E"] = {"111","100","110","100","111"},
  ["F"] = {"111","100","110","100","100"},
  ["G"] = {"111","100","101","101","111"},
  ["H"] = {"101","101","111","101","101"},
  ["I"] = {"111","010","010","010","111"},
  ["J"] = {"001","001","001","101","111"},
  ["K"] = {"101","110","100","110","101"},
  ["L"] = {"100","100","100","100","111"},
  ["M"] = {"101","111","111","101","101"},
  ["N"] = {"101","111","111","111","101"},
  ["O"] = {"111","101","101","101","111"},
  ["P"] = {"111","101","111","100","100"},
  ["Q"] = {"111","101","101","111","001"},
  ["R"] = {"110","101","110","101","101"},
  ["S"] = {"111","100","111","001","111"},
  ["T"] = {"111","010","010","010","010"},
  ["U"] = {"101","101","101","101","111"},
  ["V"] = {"101","101","101","101","010"},
  ["W"] = {"101","101","111","111","101"},
  ["X"] = {"101","101","010","101","101"},
  ["Y"] = {"101","101","010","010","010"},
  ["Z"] = {"111","001","010","100","111"},

  -- SYMBOLS
  [":"] = {"0","1","0","1","0"},
  ["."] = {"0","0","0","0","1"},
  ["-"] = {"0","0","111","0","0"},
  ["+"] = {"0","010","111","010","0"},
  ["/"] = {"001","001","010","100","100"},

  [" "] = {"0","0","0","0","0"}
}

local function fmtBoardTime(t)
  if not t then
    return "--:--.--"
  end

  local totalHundredths = math.floor(t * 100 + 0.5)

  local minutes = math.floor(totalHundredths / 6000)
  local secs = math.floor((totalHundredths % 6000) / 100)
  local hundredths = totalHundredths % 100

  return string.format("%02d:%02d.%02d", minutes, secs, hundredths)
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

local function drawShadowedStringScaled(mon, str, px, py, scale, mainColour, shadowColour)
  drawStringScaled(mon, str, px + scale, py + scale, scale, shadowColour)
  drawStringScaled(mon, str, px, py, scale, mainColour)
end

local state = {
  mode = "race",          -- "race" or "time_trial"
  localEnabled = redstone.getInput(TOGGLE_SIDE),
  sessionArmed = false,
  raceActive = false,
  finished = false,
  dnf = false,

  lapTarget = 1,
  lapsCompleted = 0,
  checkpointHit = false,

  raceStartEpoch = nil,
  lapStartEpoch = nil,

  lastLap = nil,
  bestLapSession = nil,
  totalTime = nil,
  sessionLaps = {},

  allTimeBest = record.allTimeBest,
  stateLabel = redstone.getInput(TOGGLE_SIDE) and "READY" or "IDLE",

  allTimeLapsCompleted = record.allTimeLapsCompleted,
  previousLapAllSessions = record.previousLapAllSessions,
}

local lastInputs = {
  start = redstone.getInput(DETECTOR_START_SIDE),
  mid = redstone.getInput(DETECTOR_MID_SIDE),
  toggle = redstone.getInput(TOGGLE_SIDE),
}

local lastPulseAt = {
  start = 0,
  mid = 0,
}


local function drawLaneHeader(title, maxWidth)
  local titleScale = 1
  local titleWidth = stringUnitsWide(title) * titleScale
  local titleHeight = 5 * titleScale

  while titleScale > 1 and titleWidth > maxWidth do
    titleScale = titleScale - 1
    titleWidth = stringUnitsWide(title) * titleScale
    titleHeight = 5 * titleScale
  end

  local titleX = math.floor((maxWidth - titleWidth) / 2) + 1
  local titleY = 2

  local darkYellowShadow = setPaletteFromColour(mon, colors.gray, colors.yellow, 0.38)
  drawShadowedStringScaled(mon, title, titleX, titleY, titleScale, colors.yellow, darkYellowShadow)

  mon.setBackgroundColor(colors.black)
  mon.setTextColor(colors.white)

  return titleY + titleHeight + 2
end

local function nowMs()
  return os.epoch("utc")
end

local function fmtTime(t)
  if not t then return "--.--" end
  return string.format("%.2f", t)
end

local function canDetect()
  return state.localEnabled and state.sessionArmed and state.raceActive
     and not state.finished and not state.dnf
end

local function sessionBest()
  if #state.sessionLaps == 0 then return nil end
  local best = state.sessionLaps[1]
  for i = 2, #state.sessionLaps do
    if state.sessionLaps[i] < best then best = state.sessionLaps[i] end
  end
  return best
end

local function send(msg)
  msg.player = PLAYER_NAME
  rednet.broadcast(msg, PROTOCOL)
end

local function sendStatus()
  send({
    type = "lane_status",
    enabled = state.localEnabled,
    armed = state.sessionArmed,
    active = state.raceActive,
    finished = state.finished,
    dnf = state.dnf,
    mode = state.mode,
    lapsCompleted = state.lapsCompleted,
    lastLap = state.lastLap,
    bestLapSession = state.bestLapSession,
    allTimeBest = state.allTimeBest,
    totalTime = state.totalTime,
  })
end

local function resetSession(keepToggleState)
  state.sessionArmed = false
  state.raceActive = false
  state.finished = false
  state.dnf = false

  state.lapTarget = 1
  state.lapsCompleted = 0
  state.checkpointHit = false

  state.raceStartEpoch = nil
  state.lapStartEpoch = nil

  state.lastLap = nil
  state.bestLapSession = nil
  state.totalTime = nil
  state.sessionLaps = {}

  if not keepToggleState then
    state.localEnabled = redstone.getInput(TOGGLE_SIDE)
  end

  if state.localEnabled then
    state.stateLabel = "READY"
  else
    state.stateLabel = "IDLE"
  end
end

local function fmtDeltaToPreviousBest(lapTime, previousBest)
  if not lapTime then
    return ""
  end

  if not previousBest then
    return "NEW"
  end

  local delta = lapTime - previousBest
  if math.abs(delta) < 0.005 then
    return "+0.00"
  end

  return string.format("%+.2f", delta)
end

local function fmtDeltaToPreviousBest(lapTime, previousBest)
  if not lapTime then
    return ""
  end
  if not previousBest then
    return "NEW"
  end

  local delta = lapTime - previousBest
  if math.abs(delta) < 0.005 then
    return "+0.00"
  end
  return string.format("%+.2f", delta)
end

local function drawMonitor()
  mon.setBackgroundColor(colors.black)
  mon.setTextColor(colors.white)
  mon.clear()

  local w, h = mon.getSize()

  local gap = 2
  local usableW = w - gap
  local leftW = math.max(12, math.floor((usableW * 3) / 5))
  local rightX = leftW + gap + 1
  local rightW = w - rightX + 1

  local function writeAt(x, y, text, colour)
    if y < 1 or y > h or x > w then return end
    mon.setCursorPos(x, y)
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colour or colors.white)
    mon.write(tostring(text):sub(1, math.max(0, w - x + 1)))
  end

  local function writeLeft(y, label, value, colour)
    local text = label .. value
    writeAt(1, y, text:sub(1, leftW), colour)
  end

  local function writeRight(y, text, colour)
    writeAt(rightX, y, text:sub(1, rightW), colour)
  end

  local runningTotal = state.totalTime
  if state.raceActive and state.raceStartEpoch then
    runningTotal = (nowMs() - state.raceStartEpoch) / 1000
  end

  local currentLap = 0
  if state.raceActive or state.sessionArmed or state.finished or state.dnf then
    currentLap = (state.lapsCompleted or 0) + 1
  end
  if state.finished then
    currentLap = state.lapTarget or currentLap
  elseif state.mode == "race" and state.lapTarget then
    currentLap = math.min(currentLap, state.lapTarget)
  end

  -- divider
  for yy = 1, h do
    if leftW + 1 <= w then
      writeAt(leftW + 1, yy, "|", colors.gray)
    end
  end

  -- LEFT COLUMN
  local y = drawLaneHeader(string.upper(PLAYER_NAME), leftW)

  writeLeft(y, "Mode: ", state.mode == "race" and "RACE" or "TIME TRIAL", colors.cyan); y = y + 1
  writeLeft(y, "State: ", state.stateLabel, colors.lightGray); y = y + 1
  writeLeft(
    y,
    "Participating: ",
    state.localEnabled and "YES" or "NO",
    state.localEnabled and colors.lime or colors.red
  ); y = y + 1

  y = y + 1
  writeLeft(y, "All-time best: ", fmtBoardTime(state.allTimeBest), colors.white); y = y + 1
  writeLeft(y, "Prev lap: ", fmtBoardTime(state.previousLapAllSessions), colors.white); y = y + 1
  writeLeft(y, "All-time laps: ", tostring(state.allTimeLapsCompleted or 0), colors.white); y = y + 1

  -- RIGHT COLUMN
  local ry = 1
  writeRight(ry, "Session", colors.orange); ry = ry + 1
  writeRight(ry, "Best:  " .. fmtBoardTime(state.bestLapSession), colors.white); ry = ry + 1
  writeRight(ry, "Lap:   " .. tostring(currentLap), colors.white); ry = ry + 1
  writeRight(ry, "Total: " .. fmtBoardTime(runningTotal), colors.white); ry = ry + 1

  ry = ry + 1
  writeRight(ry, "Times", colors.orange); ry = ry + 1

  if #state.sessionLaps == 0 then
    writeRight(ry, "No laps yet.", colors.gray)
    return
  end

  local availableRows = h - ry + 1
  local startIndex = math.max(1, #state.sessionLaps - availableRows + 1)

  for i = startIndex, #state.sessionLaps do
    if ry > h then break end

    local entry = state.sessionLaps[i]
    local lapTime = entry.lapTime
    local previousBest = entry.previousBest
    local deltaText = fmtDeltaToPreviousBest(lapTime, previousBest)

    local colour = colors.white
    if not previousBest or lapTime < previousBest then
      colour = colors.lime
    end

    local row = string.format(
      "%-2d %7s %6s",
      i,
      fmtBoardTime(lapTime),
      deltaText
    )

    writeRight(ry, row, colour)
    ry = ry + 1
  end
end

local function onValidLap()
  local tNow = nowMs()
  local lapTime = (tNow - state.lapStartEpoch) / 1000
  local previousBest = state.allTimeBest
  state.lapStartEpoch = tNow
  state.lapsCompleted = state.lapsCompleted + 1
  state.lastLap = lapTime
  state.totalTime = (tNow - state.raceStartEpoch) / 1000
  state.previousLapAllSessions = lapTime
  state.allTimeLapsCompleted = (state.allTimeLapsCompleted or 0) + 1

  record.previousLapAllSessions = state.previousLapAllSessions
  record.allTimeLapsCompleted = state.allTimeLapsCompleted
  saveRecord(record)
  table.insert(state.sessionLaps, {
    lapTime = lapTime,
    previousBest = previousBest
  })

  if not state.bestLapSession or lapTime < state.bestLapSession then
    state.bestLapSession = lapTime
  end

  if not state.allTimeBest or lapTime < state.allTimeBest then
    state.allTimeBest = lapTime
    record.allTimeBest = lapTime
    saveRecord(record)
  end

  send({
    type = "lap_complete",
    lap = state.lapsCompleted,
    lapTime = lapTime,
    previousBest = previousBest,
    bestLapSession = state.bestLapSession,
    allTimeBest = state.allTimeBest,
    totalTime = state.totalTime,
    mode = state.mode,
  })

  if state.mode == "race" and state.lapsCompleted >= state.lapTarget then
    state.finished = true
    state.raceActive = false
    state.sessionArmed = false
    state.stateLabel = "FINISHED"

    send({
      type = "finished",
      lap = state.lapsCompleted,
      finalTime = state.totalTime,
      bestLapSession = state.bestLapSession,
      allTimeBest = state.allTimeBest,
    })
  end

  sendStatus()
end

local function handleDetector(which)
  if not canDetect() then return end

  if which == "mid" then
    state.checkpointHit = true
    send({ type = "checkpoint", detector = "MID" })
    return
  end

  if which == "start" then
    if state.checkpointHit and state.lapStartEpoch then
      state.checkpointHit = false
      onValidLap()
    end
  end
end

local function handleControlMessage(msg)
  if type(msg) ~= "table" then return end
  if msg.target and msg.target ~= "*" and msg.target ~= PLAYER_NAME then return end

  if msg.type == "set_mode" then
    state.mode = msg.mode or "race"
    resetSession(true)
    sendStatus()

  elseif msg.type == "arm_lane" then
    state.mode = msg.mode or state.mode
    state.sessionArmed = true
    state.raceActive = false
    state.finished = false
    state.dnf = false

    state.lapTarget = msg.lapTarget or 1
    state.lapsCompleted = 0
    state.checkpointHit = false
    state.raceStartEpoch = nil
    state.lapStartEpoch = nil
    state.lastLap = nil
    state.bestLapSession = nil
    state.totalTime = nil
    state.sessionLaps = {}

    state.stateLabel = "ARMED"
    sendStatus()

  elseif msg.type == "prepare_start" then
    if state.sessionArmed and state.localEnabled then
      state.stateLabel = "COUNTDOWN"
      sendStatus()
    end

  elseif msg.type == "go" then
    if state.sessionArmed and state.localEnabled and not state.dnf then
      state.raceActive = true
      state.finished = false
      state.raceStartEpoch = msg.startEpoch or nowMs()
      state.lapStartEpoch = state.raceStartEpoch
      state.stateLabel = "RACING"
      sendStatus()
    end

  elseif msg.type == "mark_dnf" then
    state.dnf = true
    state.sessionArmed = false
    state.raceActive = false
    state.finished = false
    state.stateLabel = "DNF"
    sendStatus()

  elseif msg.type == "disarm_lane" then
    state.sessionArmed = false
    state.raceActive = false
    if not state.finished and not state.dnf then
      state.stateLabel = state.localEnabled and "READY" or "IDLE"
    end
    sendStatus()

  elseif msg.type == "reset_lane" then
    resetSession(false)
    sendStatus()
  end
end

local function redstoneLoop()
  while true do
    os.pullEvent("redstone")

    local startNow = redstone.getInput(DETECTOR_START_SIDE)
    local midNow = redstone.getInput(DETECTOR_MID_SIDE)
    local toggleNow = redstone.getInput(TOGGLE_SIDE)
    local tNow = nowMs()

    if startNow and not lastInputs.start and (tNow - lastPulseAt.start) >= DETECTOR_DEBOUNCE_MS then
      lastPulseAt.start = tNow
      handleDetector("start")
    end

    if midNow and not lastInputs.mid and (tNow - lastPulseAt.mid) >= DETECTOR_DEBOUNCE_MS then
      lastPulseAt.mid = tNow
      handleDetector("mid")
    end

    if toggleNow ~= lastInputs.toggle then
      state.localEnabled = toggleNow

      if state.localEnabled and not state.sessionArmed and not state.raceActive and not state.finished and not state.dnf then
        state.stateLabel = "READY"
      elseif not state.localEnabled and not state.sessionArmed and not state.raceActive and not state.finished and not state.dnf then
        state.stateLabel = "IDLE"
      end

      send({
        type = "toggle_changed",
        enabled = state.localEnabled,
      })
      sendStatus()
    end

    lastInputs.start = startNow
    lastInputs.mid = midNow
    lastInputs.toggle = toggleNow
  end
end

local function networkLoop()
  while true do
    local _, msg, protocol = rednet.receive(PROTOCOL)
    if protocol == PROTOCOL then
      handleControlMessage(msg)
    end
  end
end

local function uiLoop()
  while true do
    drawMonitor()
    sleep(0.2)
  end
end

send({
  type = "hello",
  enabled = state.localEnabled,
  allTimeBest = state.allTimeBest,
})

sendStatus()
drawMonitor()
parallel.waitForAny(redstoneLoop, networkLoop, uiLoop)