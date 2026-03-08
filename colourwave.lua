local mon = peripheral.find("monitor")
if not mon then
  error("No monitor found")
end

mon.setTextScale(0.5)
local w, h = mon.getSize()

local coloursList = {
  colors.red,
  colors.orange,
  colors.yellow,
  colors.lime,
  colors.green,
  colors.cyan,
  colors.blue,
  colors.purple,
  colors.magenta,
  colors.pink
}

local t = 0

while true do
  for y = 1, h do
    for x = 1, w do
      local n = math.floor(
        1
        + ((math.sin(x / 4 + t) + math.cos(y / 3 + t * 1.3) + 2) / 4)
          * (#coloursList - 1)
      )

      mon.setCursorPos(x, y)
      mon.setBackgroundColor(coloursList[n])
      mon.write(" ")
    end
  end

  t = t + 0.2
  sleep(0.05)
end