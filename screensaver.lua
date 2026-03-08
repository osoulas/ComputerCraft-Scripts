local mon = peripheral.find("monitor")
if not mon then
  error("No monitor found")
end

mon.setTextScale(2)
mon.setBackgroundColor(colors.black)
mon.clear()
mon.setCursorBlink(false)

-- Dark grey for the big clock
mon.setPaletteColor(colors.lightGray, 0.22, 0.22, 0.22)

-- Draw paintutils to the monitor
term.redirect(mon)

local w, h = term.getSize()

-- Pixel logo text
local logoText = "OSKAR"

-- Pixel movement coordinates for the logo
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
  colors.pink,
  colors.white
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

-- 3x5 font for clock and logo
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
  ["S"] = {"111","100","111","001","111"},
  ["T"] = {"111","010","010","010","010"},
  ["V"] = {"101","101","101","101","010"}
}

local function getMinecraftTimeString(blinkOn)
  local t = os.time() % 24

  -- Your empirically matched 20-hour sunrise clock
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

local function getClockScale(str)
  local totalUnitsWide = stringUnitsWide(str)
  local totalUnitsHigh = 5

  local scaleX = math.max(1, math.floor((w - 4) / totalUnitsWide))
  local scaleY = math.max(1, math.floor((h - 4) / totalUnitsHigh))

  return math.max(1, math.min(scaleX, scaleY))
end

local function drawPixelSafe(px, py, colour)
  if px >= 1 and px <= w and py >= 1 and py <= h then
    paintutils.drawPixel(px, py, colour)
  end
end

local function drawChar(ch, px, py, colour)
  local patt = font[ch] or font[" "]
  local pw = #patt[1]

  for row = 1, 5 do
    local line = patt[row]
    for col = 1, pw do
      if line:sub(col, col) == "1" then
        drawPixelSafe(px + col - 1, py + row - 1, colour)
      end
    end
  end
end

local function drawString(str, px, py, colour)
  local cx = px
  for i = 1, #str do
    local ch = str:sub(i, i)
    drawChar(ch, cx, py, colour)
    cx = cx + charWidth(ch)
    if i < #str then
      cx = cx + 1
    end
  end
end

local function drawBigClock(str)
  local scale = getClockScale(str)

  local totalWidth = stringUnitsWide(str) * scale
  local totalHeight = 5 * scale

  local startX = math.floor((w - totalWidth) / 2) + 1
  local startY = math.floor((h - totalHeight) / 2) + 1

  drawString(str, startX, startY, scale, colors.lightGray)
end

local function getLogoScale()
  -- Slightly larger than plain text, but still practical on a 3x4 monitor
  return 2
end

local function getLogoSize(str, scale)
  local width = stringUnitsWide(str) * scale
  local height = 5 * scale
  return width, height
end

local function drawLogo(str, px, py, scale, colour)
  drawString(str, px, py, colour)
end

while true do
  w, h = term.getSize()

  term.setBackgroundColor(colors.black)
  term.clear()

  local blinkOn = math.floor(os.clock() * 2) % 2 == 0
  local timeStr = getMinecraftTimeString(blinkOn)
  drawBigClock(timeStr)

  local logoW = stringUnitsWide(logoText)
  local logoH = 5
  
  local shadowColour = darker[palette[colourIndex]] or colors.black
  drawString(logoText, x + 1, y + 1, shadowColour)
  drawString(logoText, x, y, palette[colourIndex])

  if x + dx < 1 or x + dx + logoW - 1 > w then
    dx = -dx
    colourIndex = colourIndex % #palette + 1
  end

  if y + dy < 1 or y + dy + logoH - 1 > h then
    dy = -dy
    colourIndex = colourIndex % #palette + 1
  end

  x = x + dx
  y = y + dy

  sleep(0.2)
end