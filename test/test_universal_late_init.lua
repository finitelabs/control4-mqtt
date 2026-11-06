-- MQTT Universal's start: what OnDriverLateInit does when a property's handler fails, by loading the driver as each
-- build compiles it and reading what is logged and reported.
--
-- Run from the driver root:
--   make test
-- or:
--   ./test/run_test.sh test_universal_late_init.lua

require("c4_shim")
require("drivers-common-public.global.timer")
local T = require("testlib")
local F = require("c4_fixtures")

local ROOT = (debug.getinfo(1, "S").source:match("@(.*[/\\])") or "./") .. "../"
local DRIVER = ROOT .. "drivers/mqtt_universal/driver.lua"

package.preload["cloud-client-byte"] = function()
  return {}
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
function C4:UpdateProperty(name, value)
  Properties[name] = value
end

--- Every property driver.xml declares, empty, with logging set as given.
--- @param logLevel string
--- @param logMode string
local function freshProperties(logLevel, logMode)
  Properties = {}
  local f = assert(io.open(ROOT .. "drivers/mqtt_universal/driver.xml"))
  for name in f:read("*a"):gmatch("<property>%s*<name>(.-)</name>") do
    Properties[name] = ""
  end
  f:close()
  Properties["Log Level"] = logLevel
  Properties["Log Mode"] = logMode
end

--- Load `build` and start it with OnPropertyChanged raising `message` for one property, "Boom".
--- @return boolean ok Whether OnDriverLateInit returned.
--- @return string output What it printed.
local function startWithFailingProperty(build, message)
  freshProperties("1 - Error", "Print")
  Properties["Boom"] = ""
  F.dofileBuild(DRIVER, build)
  local real = OnPropertyChanged
  OnPropertyChanged = function(p)
    if p == "Boom" then
      error(message, 0)
    end
    return real(p)
  end
  OnDriverInit()
  local ok, _, output = T.capture(function()
    OnDriverLateInit("DIT_STARTUP")
  end)
  OnPropertyChanged = real
  CancelTimer("LogMode")
  return ok, output
end

--------------------------------------------------------------------------------
T.section("an error from a property at start is logged and the start carries on")
--------------------------------------------------------------------------------

do
  local ok, output = startWithFailingProperty("oss", "payload is 100%")
  T.check("OnDriverLateInit returns, even with a % in the error", ok)
  T.eq("and the driver is initialized", gInitialized, true)
  T.contains(
    "the log names the property and keeps the error as written",
    output,
    "Error in OnPropertyChanged for property 'Boom': payload is 100%"
  )
end

--------------------------------------------------------------------------------
T.section("in a DriverCentral build it is also reported to Cloud Monitoring")
--------------------------------------------------------------------------------

do
  local diagnostics = require("lib.diagnostics")
  local reported = {}
  diagnostics.captureError = function(_, message, _, source)
    table.insert(reported, { message = message, source = source })
  end
  local ok = startWithFailingProperty("drivercentral", "boom")
  diagnostics.captureError = nil
  T.check("OnDriverLateInit returns", ok)
  T.eq(
    "one error, with where it came from",
    reported,
    { { message = "boom", source = "MqttUniversal.OnPropertyChanged" } }
  )
end

T.finish()
