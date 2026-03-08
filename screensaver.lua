local mon = peripheral.find("monitor")
if not mon then
  error("No monitor found")
end

mon.setTextScale(2)
mon.setBackgroundColor(colors.black)
mon.clear()
mon.setCursorBlink(false)

-- Dark grey for the big clock background
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

local hex = "0123456789abcdef"

local function colourToBlit(c)
  local n = math.floor(math.log(c, 2))
  return hex:sub(n + 1, n + 1)
end

local function getMinecraftTimeString(blinkOn)
  local t = os.time() % 24

  -- Convert CC's 24h in-game time into a 20h sunrise-based clock
  local totalMinutes = math.floor((t / 24) * 20 * 60 + 0.5)

  -- Empirical offset to match JourneyMap
  totalMinutes = (totalMinutes - 5 * 60) % (20 * 60)

  local hours = math.floor(totalMinutes / 60)
  local minutes = totalMinutes % 60

  local sep = blinkOn and ":" or " "
  return string.format("%02d%s%02d", hours, sep, minutes)
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

local function getClockMask(str)
  local mask = {}
  for yy = 1, h do
    mask[yy] = {}
  end

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

          for dy2 = 0, scale - 1 do
            local yy = py + dy2
            if yy >= 1 and yy <= h then
              for dx2 = 0, scale - 1 do
                local xx = px + dx2
                if xx >= 1 and xx <= w then
                  mask[yy][xx] = true
                end
              end
            end
          end
        end
      end
    end

    cursorX = cursorX + pw * scale
    if i < #str then
      cursorX = cursorX + scale
    end
  end

  return mask
end

local function drawBigClock(mask)
  mon.setBackgroundColor(colors.black)
  mon.clear()

  local whiteBlit = colourToBlit(colors.white)
  local greyBlit = colourToBlit(colors.lightGray)
  local blackBlit = colourToBlit(colors.black)

  for yy = 1, h do
    local chars = {}
    local textCols = {}
    local bgCols = {}

    for xx = 1, w do
      chars[#chars + 1] = " "
      textCols[#textCols + 1] = whiteBlit
      if mask[yy][xx] then
        bgCols[#bgCols + 1] = greyBlit
      else
        bgCols[#bgCols + 1] = blackBlit
      end
    end

    mon.setCursorPos(1, yy)
    mon.blit(table.concat(chars), table.concat(textCols), table.concat(bgCols))
  end
end

local function drawShadow(mask)
  local sx = x + 1
  local sy = y + 1

  if sy < 1 or sy > h then
    return
  end

  local chars = text
  local shadowColour = darker[palette[colourIndex]] or colors.black
  local fg = colourToBlit(shadowColour)
  local textCols = string.rep(fg, #text)

  local bgCols = {}
  local greyBlit = colourToBlit(colors.lightGray)
  local blackBlit = colourToBlit(colors.black)

  for i = 1, #text do
    local xx = sx + i - 1
    if xx >= 1 and xx <= w and mask[sy][xx] then
      bgCols[#bgCols + 1] = greyBlit
    else
      bgCols[#bgCols + 1] = blackBlit
    end
  end

  mon.setCursorPos(sx, sy)
  mon.blit(chars, textCols, table.concat(bgCols))
end

local function drawMovingText(mask)
  if y < 1 or y > h then
    return
  end

  local chars = text
  local fg = colourToBlit(palette[colourIndex])
  local textCols = string.rep(fg, #text)

  local bgCols = {}
  local greyBlit = colourToBlit(colors.lightGray)
  local blackBlit = colourToBlit(colors.black)

  for i = 1, #text do
    local xx = x + i - 1
    if xx >= 1 and xx <= w and mask[y][xx] then
      bgCols[#bgCols + 1] = greyBlit
    else
      bgCols[#bgCols + 1] = blackBlit
    end
  end

  mon.setCursorPos(x, y)
  mon.blit(chars, textCols, table.concat(bgCols))
end

while true do
  w, h = mon.getSize()

  local blinkOn = math.floor(os.clock() * 2) % 2 == 0
  local timeStr = getMinecraftTimeString(blinkOn)

  local clockMask = getClockMask(timeStr)
  drawBigClock(clockMask)
  drawShadow(clockMask)
  drawMovingText(clockMask)

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