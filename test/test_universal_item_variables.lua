-- The variables an MQTT Universal item owns: when they appear and when they go, by driving the open-source build's
-- property handlers and reading Variables.
--
-- Run from the driver root:
--   make test
-- or:
--   ./test/run_test.sh test_universal_item_variables.lua

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

local values = require("lib.values")

--- The display name of the item called `name`, as Remove Item lists it.
local function displayName(name)
  for _, item in pairs(require("lib.persist"):get("Items", {})) do
    if item.name == name then
      return item.displayName
    end
  end
end

local function setProperty(name, value)
  Properties[name] = value
  OnPropertyChanged(name)
end

local function remove(name)
  setProperty("Remove Item", displayName(name))
end

--------------------------------------------------------------------------------
T.section("a state variable is there as soon as its item is added")
--------------------------------------------------------------------------------

do
  setProperty("Add Relay", "Pump")
  T.eq("a relay's State, empty", Variables["Pump State"], "")
  setProperty("Add Contact", "Front Door")
  T.eq("a contact's State, empty", Variables["Front Door State"], "")
  setProperty("Add Event", "Doorbell")
  T.eq("an event's State, empty", Variables["Doorbell State"], "")
end

do
  values:delete("Pump State")
  ShimRestartDirector()
  OnDriverInit()
  OnDriverLateInit("DIT_STARTUP")
  T.eq("an item with no state variable gets one at the next start", Variables["Pump State"], "")
end

--------------------------------------------------------------------------------
T.section("removing an item removes every variable it owns")
--------------------------------------------------------------------------------

do
  remove("Pump")
  T.eq("the relay's State goes", Variables["Pump State"], nil)
end

do
  setProperty("Add Temperature Variable", "Probe")
  setProperty("Configure Item", displayName("Probe"))
  setProperty("State Topic", "probe/temperature")
  EC.MQTT_MESSAGE({ topic = "probe/temperature", payload = "21.5", retain = "false" })
  T.eq("a temperature item's reading is a variable", Variables["Probe"], "21.5")
  remove("Probe")
  T.eq("and goes with its item", Variables["Probe"], nil)
end

do
  setProperty("Add Humidity Variable", "Bath")
  setProperty("Configure Item", displayName("Bath"))
  setProperty("State Topic", "bath/humidity")
  EC.MQTT_MESSAGE({ topic = "bath/humidity", payload = "48", retain = "false" })
  remove("Bath")
  T.eq("a humidity item's too", Variables["Bath"], nil)
end

T.finish()
