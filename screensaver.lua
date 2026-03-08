local mon = peripheral.find("monitor")
if not mon then
  error("No monitor found")
end

mon.setTextScale(0.5)
mon.setBackgroundColor(colors.black)
mon.clear()

local w, h = mon.getSize()

local text = "OSKAR TV"
local x, y = 2, 2
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

local colourIndex = 1
local textWidth = #text

while true do
  mon.setBackgroundColor(colors.black)
  mon.clear()

  mon.setCursorPos(x, y)
  mon.setTextColor(palette[colourIndex])
  mon.write(text)

  -- Check next horizontal position
  if x + dx < 1 or x + dx + textWidth - 1 > w then
    dx = -dx
    colourIndex = colourIndex % #palette + 1
  end

  -- Check next vertical position
  if y + dy < 1 or y + dy > h then
    dy = -dy
    colourIndex = colourIndex % #palette + 1
  end

  x = x + dx
  y = y + dy

  sleep(0.05)
end