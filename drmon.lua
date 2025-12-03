-- modifiable variables
local reactorSide = "back"
local fluxgateSide = "right"

local targetStrength = 50
local maxTemperature = 8000
local safeTemperature = 3000
local lowestFieldPercent = 15

local activateOnCharged = 1

-- please leave things untouched from here on
os.loadAPI("lib/f")

local version = "0.25"
-- toggleable via the monitor, use our algorithm to achieve our target field strength or let the user tweak it
local autoInputGate = 1
local curInputGate = 222000

-- monitor 
local mon, monitor, monX, monY

-- peripherals
local reactor
local fluxgate
local inputfluxgate

-- reactor information
local ri

-- last performed action
local action = "None since reboot"
local emergencyCharge = false
local emergencyTemp = false

monitor = f.periphSearch("monitor")
inputfluxgate = f.periphSearch("flow_gate")
fluxgate = peripheral.wrap(fluxgateSide)
reactor = peripheral.wrap(reactorSide)

if monitor == null then
	error("No valid monitor was found")
end

if fluxgate == null then
	error("No valid fluxgate was found")
end

if reactor == null then
	error("No valid reactor was found")
end

if inputfluxgate == null then
	error("No valid flux gate was found")
end

monX, monY = monitor.getSize()
mon = {}
mon.monitor,mon.X, mon.Y = monitor, monX, monY
function is_charged(ri ,fieldPercent)
return ri.status == "warming_up" and ri.temperature > 2000 and fieldPercent >= 50 	
end
--write settings to config file
function save_config()
  sw = fs.open("config.txt", "w")   
  sw.writeLine(version)
  sw.writeLine(autoInputGate)
  sw.writeLine(curInputGate)
  sw.close()
end

--read settings from file
function load_config()
  sr = fs.open("config.txt", "r")
  version = sr.readLine()
  autoInputGate = tonumber(sr.readLine())
  curInputGate = tonumber(sr.readLine())
  sr.close()
end


-- 1st time? save our settings, if not, load our settings
if fs.exists("config.txt") == false then
  save_config()
else
  load_config()
end

function buttons()

  while true do
    -- button handler
    event, side, xPos, yPos = os.pullEvent("monitor_touch")

    -- output gate controls
    -- 2-4 = -1000, 6-9 = -10000, 10-12,8 = -100000
    -- 17-19 = +1000, 21-23 = +10000, 25-27 = +100000
    if yPos == 8 then
      local cFlow = fluxgate.getSignalLowFlow()
      if xPos >= 2 and xPos <= 4 then
        cFlow = cFlow-1000
      elseif xPos >= 6 and xPos <= 9 then
        cFlow = cFlow-10000
      elseif xPos >= 10 and xPos <= 12 then
        cFlow = cFlow-100000
      elseif xPos >= 17 and xPos <= 19 then
        cFlow = cFlow+100000
      elseif xPos >= 21 and xPos <= 23 then
        cFlow = cFlow+10000
      elseif xPos >= 25 and xPos <= 27 then
        cFlow = cFlow+1000
      end
      fluxgate.setSignalLowFlow(cFlow)
    end

    -- input gate controls
    -- 2-4 = -1000, 6-9 = -10000, 10-12,8 = -100000
    -- 17-19 = +1000, 21-23 = +10000, 25-27 = +100000
    if yPos == 10 and autoInputGate == 0 and xPos ~= 14 and xPos ~= 15 then
      if xPos >= 2 and xPos <= 4 then
        curInputGate = curInputGate-1000
      elseif xPos >= 6 and xPos <= 9 then
        curInputGate = curInputGate-10000
      elseif xPos >= 10 and xPos <= 12 then
        curInputGate = curInputGate-100000
      elseif xPos >= 17 and xPos <= 19 then
        curInputGate = curInputGate+100000
      elseif xPos >= 21 and xPos <= 23 then
        curInputGate = curInputGate+10000
      elseif xPos >= 25 and xPos <= 27 then
        curInputGate = curInputGate+1000
      end
      inputfluxgate.setSignalLowFlow(curInputGate)
      save_config()
    end

    -- input gate toggle
    if yPos == 10 and ( xPos == 14 or xPos == 15) then
      if autoInputGate == 1 then
        autoInputGate = 0
      else
        autoInputGate = 1
      end
      save_config()
    end

  end
end

function drawButtons(y)

  -- 2-4 = -1000, 6-9 = -10000, 10-12,8 = -100000
  -- 17-19 = +1000, 21-23 = +10000, 25-27 = +100000

  f.draw_text(mon, 2, y, " < ", colors.white, colors.gray)
  f.draw_text(mon, 6, y, " <<", colors.white, colors.gray)
  f.draw_text(mon, 10, y, "<<<", colors.white, colors.gray)

  f.draw_text(mon, 17, y, ">>>", colors.white, colors.gray)
  f.draw_text(mon, 21, y, ">> ", colors.white, colors.gray)
  f.draw_text(mon, 25, y, " > ", colors.white, colors.gray)
end



function update()
  -- cache static monitor data
  local mx = mon.X
  local barX = mx - 2

  while true do
    ri = reactor.getReactorInfo()
    if not ri then error("reactor has an invalid setup") end

    -- **************
    -- CACHE VALUES
    -- **************

    local sigOut   = fluxgate.getSignalLowFlow()
    local sigIn    = inputfluxgate.getSignalLowFlow()

    local gen      = ri.generationRate
    local temp     = ri.temperature
    local fuelPct  = 100 - math.ceil(ri.fuelConversion / ri.maxFuelConversion * 10000)*.01
    local satPct   = math.ceil(ri.energySaturation / ri.maxEnergySaturation * 10000)*.01
    local fieldPct = math.ceil(ri.fieldStrength / ri.maxFieldStrength * 10000)*.01

    -- status color
    local statusColor =
        (ri.status == "running" or is_charged(ri, fieldPct)) and colors.green or
        (ri.status == "offline") and colors.gray or
        (ri.status == "warming_up") and colors.orange or
        colors.red

    -- temp color
    local tempColor =
        (temp <= 5000) and colors.green or
        (temp <= 6500) and colors.orange or
        colors.red

    -- field color
    local fieldColor =
        (fieldPct >= 50) and colors.green or
        (fieldPct > 30) and colors.orange or
        colors.red

    -- fuel color
    local fuelColor =
        (fuelPct >= 70) and colors.green or
        (fuelPct > 30) and colors.orange or
        colors.red

    -- **************
    -- CLEAR ONE TIME
    -- **************
    f.clear(mon)

    -- **************
    -- DRAW STATIC
    -- **************
    local white = colors.white
    local black = colors.black

    f.draw_text_lr(mon, 2, 2, 1, "Reactor Status", string.upper(ri.status), white, statusColor, black)
    f.draw_text_lr(mon, 2, 4, 1, "Generation", f.format_int(gen).." rf/t", white, colors.lime, black)
    f.draw_text_lr(mon, 2, 6, 1, "Temperature", f.format_int(temp).."C", white, tempColor, black)

    f.draw_text_lr(mon, 2, 7, 1, "Output Gate", f.format_int(sigOut).." rf/t", white, colors.blue, black)
    drawButtons(8)

    f.draw_text_lr(mon, 2, 9, 1, "Input Gate", f.format_int(sigIn).." rf/t", white, colors.blue, black)

    -- **************
    -- AUTO/MANUAL TILE
    -- **************
    if autoInputGate == 1 then
      f.draw_text(mon, 14, 10, "AU", white, colors.gray)
    else
      f.draw_text(mon, 14, 10, "MA", white, colors.gray)
      drawButtons(10)
    end

    -- **************
    -- ENERGY SATURATION BAR
    -- **************
    f.draw_text_lr(mon, 2, 11, 1, "Energy Saturation", satPct.."%", white, white, black)
    f.progress_bar(mon, 2, 12, barX, satPct, 100, colors.blue, colors.gray)

    -- **************
    -- FIELD BAR
    -- **************
    if autoInputGate == 1 then
      f.draw_text_lr(mon, 2, 14, 1, "Field Strength T:"..targetStrength, fieldPct.."%", white, fieldColor, black)
    else
      f.draw_text_lr(mon, 2, 14, 1, "Field Strength", fieldPct.."%", white, fieldColor, black)
    end
    f.progress_bar(mon, 2, 15, barX, fieldPct, 100, fieldColor, colors.gray)

    -- **************
    -- FUEL BAR
    -- **************
    f.draw_text_lr(mon, 2, 17, 1, "Fuel ", fuelPct.."%", white, fuelColor, black)
    f.progress_bar(mon, 2, 18, barX, fuelPct, 100, fuelColor, colors.gray)

    f.draw_text_lr(mon, 2, 19, 1, "Action ", action, colors.gray, colors.gray, black)

    -- =====================================================
    -- *** CONTROL & SAFETY LOGIC (UNCHANGED, JUST CLEAN) ***
    -- =====================================================

    if emergencyCharge then reactor.chargeReactor() end

    if ri.status == "warming_up" then
      inputfluxgate.setSignalLowFlow(900000)
      emergencyCharge = false
    end

    if emergencyTemp and ri.status == "cooling" and temp < safeTemperature then
      reactor.activateReactor()
      emergencyTemp = false
    end

    if is_charged(ri, fieldPct) and activateOnCharged == 1 then
      reactor.activateReactor()
    end

    if ri.status == "running" then
      if autoInputGate == 1 then
        local fluxval = ri.fieldDrainRate / (1 - (targetStrength / 100))
        inputfluxgate.setSignalLowFlow(fluxval)
      else
        inputfluxgate.setSignalLowFlow(curInputGate)
      end
    end

    if fuelPct <= 10 then
      reactor.stopReactor()
      action = "Fuel below 10%, refuel"
    end

    if fieldPct <= lowestFieldPercent and ri.status == "running" then
      action = "Field Str < "..lowestFieldPercent.."%"
      reactor.stopReactor()
      reactor.chargeReactor()
      emergencyCharge = true
    end

    if temp > maxTemperature then
      reactor.stopReactor()
      action = "Temp > "..maxTemperature
      emergencyTemp = true
    end

    sleep(0.1)
  end
end


parallel.waitForAny(buttons, update)


