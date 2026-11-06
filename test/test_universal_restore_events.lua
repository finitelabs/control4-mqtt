-- MQTT Universal declares its events again in OnDriverLateInit. Director drops a driver's dynamic events at a controller
-- reboot, keeping the driver's records of them, and C4:AddEvent and C4:DeleteEvent are not safe during OnDriverInit.
-- The shim takes them at any time, so this records when they are called.
--
-- Run from the driver root:
--   make test
-- or:
--   ./test/run_test.sh test_universal_restore_events.lua

local T = require("testlib")

require("c4_shim")
package.preload["cloud-client-byte"] = function()
  return {}
end

local events = require("lib.events")

local HERE = debug.getinfo(1, "S").source:match("@(.*[/\\])") or "./"

local configInfo = C4.GetDriverConfigInfo
function C4:GetDriverConfigInfo(section)
  if section == "minimum_os_version" then
    return "3.3.0"
  elseif section == "version" then
    return "20261105"
  end
  return configInfo(self, section)
end
function C4:GetVersionInfo()
  return { version = "3.3.0.0-res" }
end
function C4:UpdateProperty(name, value)
  Properties[name] = value
end

-- An event from the last run: the driver's record stays, and the reboot has dropped the event from Director.
local eventId = events:getOrAddEvent("Item", "doorbell", "Doorbell pressed", "The doorbell was pressed").eventId
ShimResetEvents()

local f = assert(io.open(HERE .. "../drivers/mqtt_universal/driver.xml"))
for name in f:read("*a"):gmatch("<property>%s*<name>(.-)</name>") do
  Properties[name] = ""
end
f:close()

local adds, deletes = 0, 0
local addEvent, deleteEvent = C4.AddEvent, C4.DeleteEvent
function C4:AddEvent(...)
  adds = adds + 1
  return addEvent(self, ...)
end
function C4:DeleteEvent(...)
  deletes = deletes + 1
  return deleteEvent(self, ...)
end

dofile(HERE .. "../drivers/mqtt_universal/driver.lua")

T.section("OnDriverInit leaves the events alone")
do
  OnDriverInit()
  T.eq("it declares none", adds, 0)
  T.eq("and deletes none", deletes, 0)
end

T.section("OnDriverLateInit declares them again")
do
  OnDriverLateInit("DIT_STARTUP")
  T.eq("the event is back under its id", (ShimEvents()[eventId] or {}).name, "Doorbell pressed")
end

T.finish()
