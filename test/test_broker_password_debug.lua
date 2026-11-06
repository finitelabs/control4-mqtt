-- What the MQTT Broker prints when its Password changes with debug printing on, by driving the open-source build's
-- property dispatcher and reading what reaches print.
--
-- Run from the driver root:
--   make test
-- or:
--   ./test/run_test.sh test_broker_password_debug.lua
--
-- With debug printing on, the shared dispatcher prints a property's name and raw value before its handler runs,
-- unless the driver marks the property in OPC.suppressDebug.

require("c4_shim")
require("drivers-common-public.global.timer")
local T = require("testlib")
local F = require("c4_fixtures")

local ROOT = (debug.getinfo(1, "S").source:match("@(.*[/\\])") or "./") .. "../"
local SECRET = "not-a-real-password-7f3a"

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
function C4:MQTT()
  local client = {}
  for _, name in ipairs({ "OnConnect", "OnDisconnect", "OnMessage", "OnPublish", "OnSubscribe" }) do
    client[name] = function() end
  end
  for _, name in ipairs({ "SetUsernameAndPassword", "Connect", "Disconnect", "Subscribe", "Unsubscribe" }) do
    client[name] = function() end
  end
  return client
end
C4.FireEvent = function() end
C4.SendToProxy = function() end

Properties = {
  ["Broker Address"] = "192.0.2.20",
  ["Port"] = "1883",
  ["Username"] = "",
  ["Password"] = "",
  ["Keep Alive"] = "60",
  ["Log Level"] = "3 - Info",
  ["Log Mode"] = "Off",
  ["Automatic Updates"] = "Off",
  ["Update Channel"] = "Production",
  ["Driver Status"] = "",
  ["Driver Version"] = "",
}
F.dofileBuild(ROOT .. "drivers/mqtt_broker/driver.lua", "oss")
OnDriverInit()
OnDriverLateInit("DIT_STARTUP")

--- Everything printed while a property changes, with debug printing on.
--- @param name string
--- @param value string
--- @return string printed
local function printedFor(name, value)
  local lines = {}
  local realPrint = print
  print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do
      parts[#parts + 1] = tostring(select(i, ...))
    end
    lines[#lines + 1] = table.concat(parts, " ")
  end
  DEBUGPRINT = true
  Properties[name] = value
  local ok, err = pcall(OnPropertyChanged, name)
  DEBUGPRINT = false
  print = realPrint
  assert(ok, err)
  return table.concat(lines, "\n")
end

--------------------------------------------------------------------------------
T.section("debug printing shows a property change")
--------------------------------------------------------------------------------

T.truthy("a Keep Alive change prints its value", printedFor("Keep Alive", "45"):find("45", 1, true) ~= nil)

--------------------------------------------------------------------------------
T.section("but never the Password")
--------------------------------------------------------------------------------

T.truthy("a Password change prints no part of the password", printedFor("Password", SECRET):find(SECRET, 1, true) == nil)

T.finish()
