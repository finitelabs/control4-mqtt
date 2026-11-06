-- What an MQTT temperature item tells its bound devices when its Temperature Scale changes, by driving the
-- open-source build's property and message handlers and reading what reaches C4.SendToProxy.
--
-- Run from the driver root:
--   make test
-- or:
--   ./test/run_test.sh test_sensor_scale_change.lua
--
-- A reading goes out only when it changes, so a scale change sends the current reading again in the new
-- scale: otherwise a bound thermostat keeps the old scale until the temperature itself moves.

require("c4_shim")
require("drivers-common-public.global.timer")
local T = require("testlib")
local F = require("c4_fixtures")

local ROOT = (debug.getinfo(1, "S").source:match("@(.*[/\\])") or "./") .. "../"

local configInfo = C4.GetDriverConfigInfo
function C4:GetDriverConfigInfo(section)
  if section == "version" then
    return "20261106"
  elseif section == "minimum_os_version" then
    return "3.3.0"
  end
  return configInfo(self, section)
end
function C4:UpdateProperty(name, value)
  Properties[name] = value
end

local f = assert(io.open(ROOT .. "drivers/mqtt_universal/driver.xml"))
for name in f:read("*a"):gmatch("<property>%s*<name>(.-)</name>") do
  Properties[name] = ""
end
f:close()
Properties["Log Level"] = "3 - Info"
Properties["Log Mode"] = "Off"

F.dofileBuild(ROOT .. "drivers/mqtt_universal/driver.lua", "oss")
OnDriverInit()
OnDriverLateInit("DIT_STARTUP")

local sent = {}
local sendToProxy = C4.SendToProxy
C4.SendToProxy = function(self, id, command, params, ...)
  if command == "VALUE_CHANGED" then
    sent[#sent + 1] = tostring(params.VALUE) .. " " .. tostring(params.SCALE)
  end
  return sendToProxy(self, id, command, params, ...)
end

local function setProperty(name, value)
  Properties[name] = value
  OnPropertyChanged(name)
end

local function reading(payload)
  EC.MQTT_MESSAGE({ topic = "probe/t", payload = payload, retain = "false" })
end

ReceivedFromProxy(5001, "BROKER_CONNECTED", {})
setProperty("Add Temperature Variable", "Probe")
setProperty("State Topic", "probe/t")
reading("72")

--------------------------------------------------------------------------------
T.section("a Temperature Scale change sends the reading again in the new scale")
--------------------------------------------------------------------------------

sent = {}
setProperty("Temperature Scale", "Fahrenheit")
T.eq("the same reading goes out once, in Fahrenheit", sent, { "72 FAHRENHEIT" })

sent = {}
reading("72")
T.eq("and an unchanged reading after it sends nothing", sent, {})

sent = {}
reading("73")
T.eq("a changed reading goes out in the scale set", sent, { "73 FAHRENHEIT" })

T.finish()
