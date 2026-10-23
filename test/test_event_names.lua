-- Tests that the events MQTT Universal adds at runtime put NAME in their
-- descriptions. Director replaces NAME with the device's name, and Composer Pro
-- titles a script with the description, so without it the title does not say
-- which device the event is from.
--
-- Run from the driver root:
--   make test
-- or:
--   ./test/run_test.sh test_event_names.lua

local T = require("testlib")

require("c4_shim")
require("lib.utils")

local MqttDevice = require("mqtt.entities.device")
local MqttEvent = require("mqtt.entities.event")

--- Declared events as name -> description.
local function declared()
  local out = {}
  for _, event in pairs(ShimEvents()) do
    out[event.name] = event.description
  end
  return out
end

T.section("The availability events name the device")
ShimResetEvents()
MqttDevice:registerAvailabilityEvents(true)
T.eq("declared", declared(), {
  ["Device Available"] = "When NAME becomes available",
  ["Device Unavailable"] = "When NAME becomes unavailable",
})

T.section("An event item's Triggered event names the device")
ShimResetEvents()
MqttEvent:new({ id = "e1", name = "Doorbell" }, 1):registerBinding()
T.eq("declared", declared(), {
  ["Doorbell Triggered"] = "When NAME MQTT event 'Doorbell' receives a matching message",
})

T.finish()
