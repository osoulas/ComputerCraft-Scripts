local mon = peripheral.find("monitor")
if not mon then
  error("No monitor found")
end

mon.setTextScale(0.5)
mon.setBackgroundColor(colors.black)
mon.clear()
mon.setCursorBlink(false)

mon.setPaletteColor(colors.lightGray, 0.22, 0.22, 0.22)

term.redirect(mon)

local w, h = term.getSize()

local logoText = "OSKAR"
local x, y = 1, 2
local dx, dy = 1, 1

local TEXT_SCALE = 2

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

local darker = {
  [colors.white] = colors.lightGray,
  [colors.orange] = colors.brown,
  [colors.magenta] = colors.purple,
  [colors.lightBlue] = colors.blue,
  [colors.yellow] = colors.orange,
  [colors.lime] = colors.green,
  [colors.pink] = colors.red,
  [colors.gray] = colors.black,
  [colors.lightGray] = colors.gray,
  [colors.cyan] = colors.blue,
  [colors.purple] = colors.black,
  [colors.blue] = colors.black,
  [colors.brown] = colors.black,
  [colors.green] = colors.black,
  [colors.red] = colors.black,
  [colors.black] = colors.black
}

local colourIndex = 1

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
  [" "] = {"0","0","0","0","0"},

  ["A"] = {"010","101","111","101","101"},
  ["K"] = {"101","110","100","110","101"},
  ["O"] = {"111","101","101","101","111"},
  ["R"] = {"110","101","110","101","101"},
  ["S"] = {"111","100","111","001","111"}
}

local function getMinecraftTimeString(blinkOn)
  local t = os.time() % 24
  local totalMinutes = math.floor((t / 24) * 20 * 60 + 0.5)
  totalMinutes = (totalMinutes - 5 * 60) % (20 * 60)

  local hours = math.floor(totalMinutes / 60)
  local minutes = totalMinutes % 60

  local sep = blinkOn and ":" or " "
  return string.format("%02d%s%02d", hours, sep, minutes)
end

local function charWidth(ch)
  local patt = font[ch] or font[" "]
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
  if px >= 1 and px <= w and py >= 1 and py <= h then
    paintutils.drawPixel(px, py, colour)
  end
end

local function drawCharScaled(ch, px, py, scale, colour)
  local patt = font[ch] or font[" "]
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

local function drawStringScaled(str, px, py, scale, colour)
  local cx = px
  for i = 1, #str do
    local ch = str:sub(i, i)
    drawCharScaled(ch, cx, py, scale, colour)
    cx = cx + charWidth(ch) * scale
    if i < #str then
      cx = cx + scale
    end
  end
end

local function getClockScale(str)
  local totalUnitsWide = stringUnitsWide(str)
  local totalUnitsHigh = 5

  local scaleX = math.max(1, math.floor((w - 4) / totalUnitsWide))
  local scaleY = math.max(1, math.floor((h - 4) / totalUnitsHigh))

  return math.max(1, math.min(scaleX, scaleY))
end

local function drawBigClock(str)
  local scale = getClockScale(str)
  local totalWidth = stringUnitsWide(str) * scale
  local totalHeight = 5 * scale

  local startX = math.floor((w - totalWidth) / 2) + 1
  local startY = math.floor((h - totalHeight) / 2) + 1

  drawStringScaled(str, startX, startY, scale, colors.lightGray)
end

while true do
  w, h = term.getSize()

  term.setBackgroundColor(colors.black)
  term.clear()

  local blinkOn = math.floor(os.clock() * 2) % 2 == 0
  local timeStr = getMinecraftTimeString(blinkOn)
  drawBigClock(timeStr)

  local logoW = stringUnitsWide(logoText) * TEXT_SCALE
  local logoH = 5 * TEXT_SCALE

  local shadowColour = darker[palette[colourIndex]] or colors.black
  drawStringScaled(logoText, x + 1, y + 1, TEXT_SCALE, shadowColour)
  drawStringScaled(logoText, x, y, TEXT_SCALE, palette[colourIndex])

  local hitWall = false

  if x + dx < 1 or x + dx + logoW - 1 > w then
    dx = -dx
    hitWall = true
  end

  if y + dy < 1 or y + dy + logoH - 1 > h then
    dy = -dy
    hitWall = true
  end

  if hitWall then
    colourIndex = colourIndex % #palette + 1
  end

  x = x + dx
  y = y + dy

  sleep(0.2) -- 5 Hz refresh
end