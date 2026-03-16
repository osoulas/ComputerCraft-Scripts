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
local BEST_MONITOR_NAME     = "monitor_18"
local MODE_MONITOR_NAME     = "monitor_17"
local SESSION_MONITOR_NAME  = "monitor_9"

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

if not startMon then error("Could not wrap start monitor") end
if not bestMon then error("Could not wrap best-times monitor") end
if not modeMon then error("Could not wrap mode monitor") end
if not sessionMon then error("Could not wrap session monitor") end

startMon.setTextScale(1)
bestMon.setTextScale(0.5)
modeMon.setTextScale(0.5)
sessionMon.setTextScale(0.5)

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
  mon.setBackgroundColor(bg or colors.black)
  mon.clear()
  mon.setCursorPos(1, 1)
end

local function drawCenteredText(mon, text, y, fg, bg)
  local w, _ = mon.getSize()
  mon.setBackgroundColor(bg or colors.black)
  mon.setTextColor(fg or colors.white)
  local x = math.max(1, math.floor((w - #text) / 2) + 1)
  mon.setCursorPos(x, y)
  mon.write(text)
end

local function drawCircle(mon, x, y, colour)
  mon.setCursorPos(x, y)
  mon.setTextColor(colour)
  mon.write("\7")
end

local function drawStartLights(litPairs, goGreen)
  clearMonitor(startMon, colors.black)

  local w, h = startMon.getSize()

  local totalCols = 5
  local xSpacing = 2
  local rowGap = 1

  local blockWidth = (totalCols - 1) * xSpacing + 1
  local startX = math.floor((w - blockWidth) / 2) + 1
  local startY = math.floor((h - (2 + rowGap)) / 2) + 1

  local darkRed = colors.brown
  local brightRed = colors.red
  local green = colors.lime

  for col = 0, 4 do
    local colour

    if goGreen then
      colour = green
    elseif (col + 1) <= litPairs then
      colour = brightRed
    else
      colour = darkRed
    end

    local x = startX + col * xSpacing
    drawCircle(startMon, x, startY, colour)
    drawCircle(startMon, x, startY + 1 + rowGap, colour)
  end
end

local function drawRunningTime(seconds)
  clearMonitor(startMon, colors.black)
  startMon.setTextScale(1)

  local text = string.format("%.2f", seconds)
  local _, h = startMon.getSize()
  drawCenteredText(startMon, "TIME", math.max(1, math.floor(h / 2) - 1), colors.cyan, colors.black)
  drawCenteredText(startMon, text, math.max(2, math.floor(h / 2) + 1), colors.white, colors.black)
end

local function drawStartIdle()
  clearMonitor(startMon, colors.black)
  drawStartLights(0, false)
end

local function drawStartFinished()
  clearMonitor(startMon, colors.black)
  local _, h = startMon.getSize()
  drawCenteredText(startMon, "FINISH", math.max(1, math.floor(h / 2)), colors.yellow, colors.black)
end

-- =========================
-- OTHER MONITORS
-- =========================

local function drawBestMonitor()
  bestMon.setBackgroundColor(colors.black)
  bestMon.clear()

  local function line(y, text, color)
    bestMon.setCursorPos(1, y)
    bestMon.setTextColor(color or colors.white)
    bestMon.write(text)
  end

  line(1, "ALL-TIME BEST LAPS", colors.yellow)
  line(2, "POS NAME         BEST", colors.cyan)

  local list = {}
  for name, p in pairs(players) do
    table.insert(list, { name = name, best = records[name] or p.allTimeBest })
  end

  table.sort(list, function(a, b)
    if a.best == nil and b.best == nil then return a.name < b.name end
    if a.best == nil then return false end
    if b.best == nil then return true end
    return a.best < b.best
  end)

  local y = 3
  for i = 1, math.min(#list, 20) do
    local e = list[i]
    line(y, string.format("%-3d %-12s %s", i, e.name:sub(1, 12), fmtTime(e.best)), colors.white)
    y = y + 1
  end
end

local function drawModeMonitor()
  modeMon.setBackgroundColor(colors.black)
  modeMon.clear()

  local function line(y, text, color)
    modeMon.setCursorPos(1, y)
    modeMon.setTextColor(color or colors.white)
    modeMon.write(text)
  end

  line(1, "MODE / INSTRUCTIONS", colors.yellow)
  line(3, "Mode: " .. (mode == "race" and "RACE" or "TIME TRIAL"), colors.cyan)
  line(4, "Phase: " .. string.upper(phase), colors.lightGray)

  local lapDisplay = currentLapTarget or lapSelectorValue()
  if mode == "race" then
    line(5, "Laps: " .. tostring(lapDisplay), colors.white)
  else
    line(5, "Laps: free session", colors.white)
  end

  line(7, "Buttons:", colors.orange)
  line(8, "Left  = toggle mode", colors.white)
  line(9, "Right = start", colors.white)
  line(10, "Back  = reset", colors.white)

  line(12, "Ready players:", colors.orange)
  local y = 13
  local names = {}
  for name, _ in pairs(players) do table.insert(names, name) end
  table.sort(names)
  for _, name in ipairs(names) do
    local p = players[name]
    local status = p.enabled and "YES" or "NO"
    line(y, string.format("%-12s %s", name:sub(1, 12), status), p.enabled and colors.lime or colors.red)
    y = y + 1
    if y > 25 then break end
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

  local function line(y, text, color)
    sessionMon.setCursorPos(1, y)
    sessionMon.setTextColor(color or colors.white)
    sessionMon.write(text)
  end

  if mode == "race" then
    line(1, "CURRENT RACE", colors.yellow)
    line(2, "PL  NAME         BEST    LAPS  FINAL", colors.cyan)

    local names = sessionParticipants()
    table.sort(names, raceSortKey)

    local y = 3
    for i, name in ipairs(names) do
      local p = players[name]
      local finalCol = "--"
      if p.finished then
        finalCol = fmtTime(p.finalTime)
      elseif p.dnf then
        finalCol = "DNF"
      elseif p.active or p.armed then
        finalCol = "RUN"
      end

      line(y, string.format(
        "%-3d %-12s %-7s %-5d %s",
        i,
        name:sub(1, 12),
        fmtTime(p.bestLapSession),
        p.lapsCompleted or 0,
        finalCol
      ), colors.white)
      y = y + 1
      if y > 24 then break end
    end

  else
    line(1, "TIME TRIAL", colors.yellow)
    if not ttPlayer then
      line(3, "No active player selected", colors.red)
      line(5, "Enable exactly one lane,", colors.white)
      line(6, "then press Start.", colors.white)
      return
    end

    local p = players[ttPlayer]
    line(3, "Player: " .. ttPlayer, colors.cyan)
    line(4, "All-time best: " .. fmtTime(p.allTimeBest), colors.white)
    line(6, "Session laps:", colors.orange)

    local y = 7
    for i, lap in ipairs(p.sessionLaps) do
      line(y, string.format("%-3d %s", i, fmtTime(lap)), colors.white)
      y = y + 1
      if y > 24 then break end
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