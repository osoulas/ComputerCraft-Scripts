local mon = peripheral.find("monitor")
if not mon then
  error("No monitor found")
end

mon.setTextScale(2)
mon.setBackgroundColor(colors.black)
mon.clear()
mon.setCursorBlink(false)

mon.setPaletteColor(colors.lightGray, 0.22, 0.22, 0.22)

local w, h = mon.getSize()

local text = "OSKAR"
local x, y = 1, 2
local dx, dy = 1, 1

local palette = {
  colors.red,
  colors.orange,
  colors.yellow,
  colors.lime,
  colors.cyan,
  colors.blue,
  colors.purple,
  colors.magenta,
  colors.pink
}

local colourIndex = 1
local textWidth = #text

local font = {
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
  [":"] = {"0","1","0","1","0"},
  [" "] = {"0","0","0","0","0"}
}

local function getMinecraftTimeString(blinkOn)
  local t = os.time() % 24
  local offsetHours = 5

  local totalMinutes = math.floor((t / 24) * 20 * 60 + 0.5)
  totalMinutes = (totalMinutes - offsetHours * 60) % (20 * 60)

  local hours = math.floor(totalMinutes / 60)
  local minutes = totalMinutes % 60

  local sep = blinkOn and ":" or " "
  return string.format("%02d%s%02d", hours, sep, minutes)
end

local function drawBlock(px, py, bw, bh, colour)
  mon.setBackgroundColor(colour)
  local line = string.rep(" ", bw)
  for yy = 0, bh - 1 do
    local drawY = py + yy
    if drawY >= 1 and drawY <= h then
      mon.setCursorPos(px, drawY)
      mon.write(line)
    end
  end
end

local function getClockScale(str)
  local totalUnitsWide = 0

  for i = 1, #str do
    local ch = str:sub(i, i)
    local patt = font[ch]
    local cw = #patt[1]
    totalUnitsWide = totalUnitsWide + cw
    if i < #str then
      totalUnitsWide = totalUnitsWide + 1
    end
  end

  local totalUnitsHigh = 5

  local scaleX = math.max(1, math.floor((w - 4) / totalUnitsWide))
  local scaleY = math.max(1, math.floor((h - 4) / totalUnitsHigh))

  return math.max(1, math.min(scaleX, scaleY))
end

local function drawBigClock(str)
  local scale = getClockScale(str)

  local totalUnitsWide = 0
  for i = 1, #str do
    local ch = str:sub(i, i)
    local patt = font[ch]
    local cw = #patt[1]
    totalUnitsWide = totalUnitsWide + cw
    if i < #str then
      totalUnitsWide = totalUnitsWide + 1
    end
  end

  local totalWidth = totalUnitsWide * scale
  local totalHeight = 5 * scale

  local startX = math.floor((w - totalWidth) / 2) + 1
  local startY = math.floor((h - totalHeight) / 2) + 1

  local cursorX = startX

  for i = 1, #str do
    local ch = str:sub(i, i)
    local patt = font[ch]
    local pw = #patt[1]

    for row = 1, 5 do
      local line = patt[row]
      for col = 1, pw do
        if line:sub(col, col) == "1" then
          local px = cursorX + (col - 1) * scale
          local py = startY + (row - 1) * scale
          drawBlock(px, py, scale, scale, colors.lightGray)
        end
      end
    end

    cursorX = cursorX + pw * scale
    if i < #str then
      cursorX = cursorX + scale
    end
  end
end

while true do
  w, h = mon.getSize()

  mon.setBackgroundColor(colors.black)
  mon.clear()

  local blinkOn = math.floor(os.clock() * 2) % 2 == 0
  local timeStr = getMinecraftTimeString(blinkOn)
  drawBigClock(timeStr)

  mon.setCursorPos(x, y)
  mon.setTextColor(palette[colourIndex])
  mon.write(text)

  if x + dx < 1 or x + dx + textWidth - 1 > w then
    dx = -dx
    colourIndex = colourIndex % #palette + 1
  end

  if y + dy < 1 or y + dy > h then
    dy = -dy
    colourIndex = colourIndex % #palette + 1
  end

  x = x + dx
  y = y + dy

  sleep(0.2)
end