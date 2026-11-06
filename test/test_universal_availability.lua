-- MQTT Universal's device availability: the Availability Status variable, the Device Available and Device
-- Unavailable events and Driver Status, by driving the open-source build's handlers and reading what reaches C4.
--
-- Run from the driver root:
--   make test
-- or:
--   ./test/run_test.sh test_universal_availability.lua
--
-- Availability is the device's state, so it follows the start-tell rule: the first availability ever heard sets
-- the variable silently, an unchanged one after a start fires nothing, and a change fires its event, a change made
-- while the controller was down included.

require("c4_shim")
require("drivers-common-public.global.timer")
local T = require("testlib")
local F = require("c4_fixtures")

local ROOT = (debug.getinfo(1, "S").source:match("@(.*[/\\])") or "./") .. "../"
local TOPIC = "garage/availability"
local MQTT_BINDING = 5001

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

local fired, deleted = {}, 0
function C4:FireEventByID(idEvent)
  table.insert(fired, (ShimEvents()[idEvent] or {}).name or idEvent)
end
local deleteEvent = C4.DeleteEvent
function C4:DeleteEvent(...)
  deleted = deleted + 1
  return deleteEvent(self, ...)
end

local f = assert(io.open(ROOT .. "drivers/mqtt_universal/driver.xml"))
for name in f:read("*a"):gmatch("<property>%s*<name>(.-)</name>") do
  Properties[name] = ""
end
f:close()
Properties["Log Level"] = "3 - Info"
Properties["Log Mode"] = "Off"
Properties["Availability Topic"] = TOPIC
Properties["Payload Available"] = "online"
Properties["Payload Not Available"] = "offline"

F.dofileBuild(ROOT .. "drivers/mqtt_universal/driver.lua", "oss")

local function connect()
  ReceivedFromProxy(MQTT_BINDING, "BROKER_CONNECTED", {})
end

--- A start: OnDriverInit and OnDriverLateInit, then the broker answering GET_STATUS.
--- @param reboot boolean|nil A Director restart, which drops every variable and event before the driver restores them.
local function start(reboot)
  if reboot then
    ShimRestartDirector()
    ShimResetEvents()
  end
  OnDriverInit()
  OnDriverLateInit("DIT_STARTUP")
  connect()
end

--- One message on the availability topic, then the events it fired.
--- @param payload string
--- @param retain string|nil
local function availability(payload, retain)
  fired = {}
  EC.MQTT_MESSAGE({ topic = TOPIC, payload = payload, qos = "0", retain = retain or "false" })
  return fired
end

local function setProperty(name, value)
  Properties[name] = value
  OnPropertyChanged(name)
end

--- Whether Device Available and Device Unavailable are declared.
local function availabilityEvents()
  local declared = {}
  for _, event in pairs(ShimEvents()) do
    declared[event.name] = true
  end
  return { declared["Device Available"], declared["Device Unavailable"] }
end

--------------------------------------------------------------------------------
T.section("the variable is there before the device says anything")
--------------------------------------------------------------------------------

do
  start()
  T.eq("Availability Status exists, empty", Variables["Availability Status"], "")
  T.eq("Driver Status shows the broker link", Properties["Driver Status"], "Connected")
end

--------------------------------------------------------------------------------
T.section("the first availability heard is set silently, and Driver Status agrees with it")
--------------------------------------------------------------------------------

do
  T.eq("a first offline fires nothing", availability("offline", "true"), {})
  T.eq("Availability Status reads Unavailable", Variables["Availability Status"], "Unavailable")
  T.eq("and so does Driver Status", Properties["Driver Status"], "Device unavailable")
end

--------------------------------------------------------------------------------
T.section("a change fires its event, a repeat fires nothing")
--------------------------------------------------------------------------------

do
  T.eq("online fires Device Available", availability("online"), { "Device Available" })
  T.eq("Driver Status is Connected", Properties["Driver Status"], "Connected")
  T.eq("online again fires nothing", availability("online"), {})
  T.eq("offline fires Device Unavailable", availability("offline"), { "Device Unavailable" })
  T.eq("Driver Status is Device unavailable", Properties["Driver Status"], "Device unavailable")
end

--------------------------------------------------------------------------------
T.section("Driver Status agrees with Availability Status across a broker reconnect")
--------------------------------------------------------------------------------

do
  ReceivedFromProxy(MQTT_BINDING, "BROKER_DISCONNECTED", {})
  T.eq("disconnected", Properties["Driver Status"], "Disconnected")
  connect()
  T.eq("reconnected to an unavailable device", Properties["Driver Status"], "Device unavailable")
  T.eq("the broker's replay fires nothing", availability("offline", "true"), {})
  T.eq("and Driver Status stays", Properties["Driver Status"], "Device unavailable")
end

--------------------------------------------------------------------------------
T.section("after a start, the last availability is remembered")
--------------------------------------------------------------------------------

do
  start(true)
  T.eq("an unchanged offline fires nothing", availability("offline", "true"), {})
  T.eq("Driver Status reads Device unavailable", Properties["Driver Status"], "Device unavailable")
end

do
  start(true)
  T.eq(
    "back online while the controller was down fires Device Available",
    availability("online", "true"),
    { "Device Available" }
  )
end

do
  start()
  T.eq(
    "gone offline across a driver update fires Device Unavailable",
    availability("offline", "true"),
    { "Device Unavailable" }
  )
  T.eq("and Driver Status says so", Properties["Driver Status"], "Device unavailable")
end

--------------------------------------------------------------------------------
T.section("clearing the Availability Topic keeps the programming and blanks the readings")
--------------------------------------------------------------------------------

do
  deleted = 0
  setProperty("Availability Topic", "")
  T.eq("no event is deleted", deleted, 0)
  T.eq("both events stay", availabilityEvents(), { true, true })
  T.eq("Availability Status is blank", Variables["Availability Status"], "")
  T.eq("Availability Topic Value is blank", Properties["Availability Topic Value"], "")
  T.eq("Driver Status shows the broker link alone", Properties["Driver Status"], "Connected")
end

do
  start(true)
  T.eq("after a reboot both events are still declared", availabilityEvents(), { true, true })
end

do
  setProperty("Availability Topic", TOPIC)
  T.eq("with a topic again, the first availability is silent", availability("offline", "true"), {})
  T.eq("and shows in Driver Status", Properties["Driver Status"], "Device unavailable")
end

T.finish()
