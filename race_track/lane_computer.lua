-- =========================
-- LANE COMPUTER: startup
-- =========================

-- --------- CONFIG ---------
local PLAYER_NAME = "Player 1"

local DETECTOR_START_SIDE = "left"   -- start/finish detector
local DETECTOR_MID_SIDE   = "right"  -- mid-track detector
local TOGGLE_SIDE         = "back"   -- participation toggle
local MODEM_SIDE          = "bottom"

-- Set this to a side ("top") or a peripheral name from `peripherals`
local MONITOR_NAME = "monitor_4"

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
  return { allTimeBest = nil }
end

local function saveRecord(data)
  local h = fs.open(RECORD_FILE, "w")
  h.write(textutils.serialize(data))
  h.close()
end

local record = loadRecord()

if not rednet.isOpen(MODEM_SIDE) then
  rednet.open(MODEM_SIDE)
end

local mon = peripheral.wrap(MONITOR_NAME)
if not mon then
  error("Could not wrap monitor: " .. tostring(MONITOR_NAME))
end

mon.setTextScale(0.5)

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

local function drawMonitor()
  mon.setBackgroundColor(colors.black)
  mon.setTextColor(colors.white)
  mon.clear()

  local w, h = mon.getSize()

  local function writeLine(y, text, color)
    if y > h then return end
    mon.setCursorPos(1, y)
    mon.setTextColor(color or colors.white)
    mon.write(text:sub(1, w))
  end

  local runningTotal = state.totalTime
  if state.raceActive and state.raceStartEpoch then
    runningTotal = (nowMs() - state.raceStartEpoch) / 1000
  end

  writeLine(1, PLAYER_NAME, colors.yellow)
  writeLine(2, "Mode: " .. (state.mode == "race" and "RACE" or "TIME TRIAL"), colors.cyan)
  writeLine(3, "State: " .. state.stateLabel, colors.lightGray)
  writeLine(4, "Enabled: " .. (state.localEnabled and "YES" or "NO"), state.localEnabled and colors.lime or colors.red)
  writeLine(5, "Lap: " .. tostring(state.lapsCompleted) .. "/" .. tostring(state.lapTarget), colors.white)
  writeLine(6, "Last: " .. fmtTime(state.lastLap), colors.white)
  writeLine(7, "Best: " .. fmtTime(state.bestLapSession), colors.white)
  writeLine(8, "All-time: " .. fmtTime(state.allTimeBest), colors.white)
  writeLine(9, "Total: " .. fmtTime(runningTotal), colors.white)

  if state.mode == "time_trial" then
    writeLine(11, "Session laps:", colors.orange)
    local line = 12
    for i = math.max(1, #state.sessionLaps - 5), #state.sessionLaps do
      writeLine(line, tostring(i) .. ". " .. fmtTime(state.sessionLaps[i]), colors.white)
      line = line + 1
    end
  end
end

local function onValidLap()
  local tNow = nowMs()
  local lapTime = (tNow - state.lapStartEpoch) / 1000
  state.lapStartEpoch = tNow
  state.lapsCompleted = state.lapsCompleted + 1
  state.lastLap = lapTime
  state.totalTime = (tNow - state.raceStartEpoch) / 1000
  table.insert(state.sessionLaps, lapTime)

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