-- When an MQTT Universal event item fires, by driving the open-source build's MQTT_MESSAGE handler and reading
-- what reaches C4:FireEventByID and C4.SendToProxy.
--
-- Run from the driver root:
--   make test
-- or:
--   ./test/run_test.sh test_event_replay.lua
--
-- An event is a moment. A message the server kept (retained), the Broker's replay of its last message to a
-- reloaded child, and the driver re-reading its own last message after a settings change are all the last event
-- again, so they fire nothing. State items still take them: their state is what those messages carry.

require("c4_shim")
require("drivers-common-public.global.timer")
local T = require("testlib")

local ROOT = (debug.getinfo(1, "S").source:match("@(.*[/\\])") or "./") .. "../"
local TOPIC = "door/event"

function C4:GetVersionInfo()
  return { version = "4.3.0.763530-res" }
end
local configInfo = C4.GetDriverConfigInfo
function C4:GetDriverConfigInfo(section)
  if section == "version" then
    return "20261106"
  elseif section == "minimum_os_version" then
    return "3.3.0"
  end
  return configInfo(self, section)
end
-- Selecting the new item goes through Configure Item, which the handlers read back from Properties.
function C4:UpdateProperty(name, value)
  Properties[name] = value
end

--- Runs `path` as the open-source build compiles it: the DriverCentral lines are blanked.
--- @param path string
local function dofileOpenSource(path)
  local f = assert(io.open(path))
  local lines, stack, including = {}, {}, true
  for line in f:lines() do
    local ifdef, name = line:match("^%s*%-%-%s*#(ifn?def)%s+([%w_]+)%s*$")
    if ifdef then
      stack[#stack + 1] = including
      including = including and (name == "DRIVERCENTRAL") == (ifdef == "ifndef")
    elseif line:match("^%s*%-%-%s*#else%s*$") then
      including = stack[#stack] and not including
    elseif line:match("^%s*%-%-%s*#endif%s*$") then
      including = table.remove(stack)
    end
    lines[#lines + 1] = including and line or ""
  end
  f:close()
  return assert(load(table.concat(lines, "\n"), "@" .. path))()
end

local fired, pressed = {}, {}
function C4:FireEventByID(idEvent)
  fired[#fired + 1] = idEvent
end
C4.SendToProxy = function(_, _, command)
  if command == "DO_PUSH" or command == "DO_CLICK" then
    pressed[#pressed + 1] = command
  end
end

local f = assert(io.open(ROOT .. "drivers/mqtt_universal/driver.xml"))
for name in f:read("*a"):gmatch("<property>%s*<name>(.-)</name>") do
  Properties[name] = ""
end
f:close()
Properties["Log Level"] = "3 - Info"
Properties["Log Mode"] = "Off"

dofileOpenSource(ROOT .. "drivers/mqtt_universal/driver.lua")
OnDriverInit()
OnDriverLateInit("DIT_STARTUP")
OPC.Add_Event("Doorbell")
OPC.State_Topic(TOPIC)

--- One message on the event's topic, then what it fired.
--- @param retain string|nil The message's retain field, as the Broker sends it.
local function message(retain)
  fired, pressed = {}, {}
  EC.MQTT_MESSAGE({ topic = TOPIC, payload = "press", qos = "0", retain = retain })
  return #fired, pressed
end

--------------------------------------------------------------------------------
T.section("a message just published fires the event and presses its button link")
--------------------------------------------------------------------------------

do
  local events, presses = message("false")
  T.eq("one event", events, 1)
  T.eq("and the keypad tap", presses, { "DO_PUSH", "DO_CLICK" })
end

do
  local events = message(nil)
  T.eq("a message with no retain field fires too", events, 1)
end

--------------------------------------------------------------------------------
T.section("a stored message fires nothing")
--------------------------------------------------------------------------------

do
  local events, presses = message("true")
  T.eq("a retained message or the Broker's replay: no event", events, 0)
  T.eq("and no button press", presses, {})
end

do
  fired, pressed = {}, {}
  OPC.Value_Path("")
  T.eq("re-reading the last message after a settings change: no event", #fired, 0)
  T.eq("and no button press", pressed, {})
end

do
  local events = message("false")
  T.eq("the next message just published still fires", events, 1)
end

--------------------------------------------------------------------------------
T.section("a state item still takes a stored message")
--------------------------------------------------------------------------------

do
  local MqttRelay = require("mqtt.entities.relay")
  local relay = MqttRelay:new({ id = "r1", name = "Pump", stateTopic = "pump/state", stateOn = "ON", stateOff = "OFF" }, 1)
  relay:onMessage("ON", true)
  T.eq("a retained ON sets a relay item on", relay:getState(), true)
end

T.finish()
