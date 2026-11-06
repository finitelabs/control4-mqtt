-- MQTT Universal's Log Mode and Log Level together: the vendored libraries' debug output follows both, by driving
-- the open-source build's property handlers and reading the DEBUG* globals Log Level sets.
--
-- Run from the driver root:
--   make test
-- or:
--   ./test/run_test.sh test_universal_log_mode.lua
--
-- At 6 - Ultra, Log Level turns on DEBUGPRINT and its kin only while printing is on, so a change of Log Mode has to
-- apply Log Level again.

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

--- Set a property the way Composer does: the new value, then its handler. Quiet, since debug output may be on.
local function set(name, value)
  Properties[name] = value
  T.capture(function()
    OnPropertyChanged(name)
  end)
end

--------------------------------------------------------------------------------
T.section("turning printing on applies an Ultra Log Level")
--------------------------------------------------------------------------------

do
  set("Log Level", "6 - Ultra")
  T.eq("with Log Mode Off, no debug output", DEBUGPRINT, false)
  set("Log Mode", "Print")
  T.eq("Log Mode Print turns DEBUGPRINT on", DEBUGPRINT, true)
  T.eq("and DEBUG_TIMER", DEBUG_TIMER, true)
end

--------------------------------------------------------------------------------
T.section("when the three hours run out, the debug output stops with it")
--------------------------------------------------------------------------------

do
  T.capture(ShimFireTimers)
  T.eq("Log Mode is Off", Properties["Log Mode"], "Off")
  T.eq("DEBUGPRINT is off", DEBUGPRINT, false)
  T.eq("and DEBUG_TIMER", DEBUG_TIMER, false)
  T.eq("Log Level is back to Info", Properties["Log Level"], "3 - Info")
end

T.finish()
