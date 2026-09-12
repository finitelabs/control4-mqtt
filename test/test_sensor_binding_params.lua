-- Tests that the MQTT sensor entity emits a binding payload every consumer can
-- read, by driving MqttSensor:sendValue and reading what reaches C4.
--
-- Run from the driver root:
--   make test
-- or:
--   ./test/run_test.sh test_sensor_binding_params.lua
--
-- The helpers' own behaviour is covered by test_sensor_params.lua. What is
-- checked here is the call site: C4-THERM reads a bound temperature from
-- CELSIUS and never looks at VALUE or SCALE, and crashes at its driver.lua:2982
-- when TIMESTAMP is absent, so the {VALUE, SCALE} payload this entity used to
-- send could not be ingested at all.
--
-- Regression test for DRV-121.

local T = require("testlib")

require("c4_shim")
require("lib.utils")

local bindings = require("lib.bindings")
local MqttSensor = require("mqtt.entities.sensor")

local BINDING_ID = 4001

bindings.getDynamicBinding = function()
  return { bindingId = BINDING_ID }
end

--- Drive a sensor and return the payload C4 received.
---
--- Captured at C4.SendToProxy rather than the global SendToProxy of the same
--- name: the global is a wrapper in lib/utils.lua that forwards through C4Call,
--- so stubbing it would measure the argument the entity passed instead of what
--- came out the far end of the path the driver actually takes.
local function sendAndCapture(item, value)
  local captured = nil
  local real = C4.SendToProxy
  C4.SendToProxy = function(_, idBinding, strCommand, tParams)
    captured = { idBinding = idBinding, command = strCommand, params = tParams }
  end
  local ok, err = pcall(function()
    MqttSensor:new(item, 1):sendValue(value)
  end)
  C4.SendToProxy = real
  if not ok then
    error(err, 0)
  end
  return captured
end

local function temperatureItem(scale)
  return { id = "t1", name = "Probe", itemType = "TEMPERATURE", temperatureScale = scale }
end

--------------------------------------------------------------------------------
T.section("a Celsius temperature carries every key convention")
--------------------------------------------------------------------------------

local celsius = sendAndCapture(temperatureItem("Celsius"), 21.5)

T.check("the send reached C4", celsius ~= nil, "no SendToProxy call")
T.eq("goes to the sensor binding", celsius.idBinding, BINDING_ID)
T.eq("as VALUE_CHANGED", celsius.command, "VALUE_CHANGED")
T.eq("VALUE is the measured number", celsius.params.VALUE, 21.5)
T.eq("SCALE names the measured scale", celsius.params.SCALE, "CELSIUS")
T.eq("CELSIUS is what C4-THERM reads", celsius.params.CELSIUS, 21.5)
T.eq("FAHRENHEIT is converted alongside", celsius.params.FAHRENHEIT, 70.7)

--------------------------------------------------------------------------------
T.section("a Fahrenheit sensor keeps VALUE in the scale it measured")
--------------------------------------------------------------------------------

-- The scale is per-item configuration, so rewriting VALUE to Celsius would
-- change the number every already-bound consumer reads. CELSIUS is added
-- alongside instead, which is what makes this change additive.
local fahrenheit = sendAndCapture(temperatureItem("Fahrenheit"), 70.7)

T.eq("VALUE is left as measured", fahrenheit.params.VALUE, 70.7)
T.eq("SCALE says so", fahrenheit.params.SCALE, "FAHRENHEIT")
T.eq("CELSIUS is converted for C4-THERM", fahrenheit.params.CELSIUS, 21.5)
T.eq("FAHRENHEIT round-trips", fahrenheit.params.FAHRENHEIT, 70.7)

--------------------------------------------------------------------------------
T.section("humidity carries no temperature keys")
--------------------------------------------------------------------------------

-- PERCENT is not a temperature scale, so a CELSIUS here would be a converted
-- humidity reading: a number a bound thermostat would happily act on.
local humidity = sendAndCapture({ id = "h1", name = "Probe", itemType = "HUMIDITY" }, 55)

T.eq("VALUE is the percentage", humidity.params.VALUE, 55)
T.eq("SCALE is PERCENT", humidity.params.SCALE, "PERCENT")
T.eq("no CELSIUS", humidity.params.CELSIUS, nil)
T.eq("no FAHRENHEIT", humidity.params.FAHRENHEIT, nil)

--------------------------------------------------------------------------------
T.section("TIMESTAMP is present and fresh on every payload")
--------------------------------------------------------------------------------

-- C4-THERM discards a reading stamped older than 900 seconds and crashes on one
-- with no stamp at all, so both properties are asserted rather than presence
-- alone. Bounded generously: what is under test is that the stamp is epoch
-- seconds from os.time(), not the clock.
local now = os.time()
for _, case in ipairs({
  { what = "celsius", captured = celsius },
  { what = "fahrenheit", captured = fahrenheit },
  { what = "humidity", captured = humidity },
}) do
  local stamp = case.captured.params.TIMESTAMP
  T.check(case.what .. ": TIMESTAMP is a number", type(stamp) == "number", type(stamp))
  T.check(
    case.what .. ": TIMESTAMP is epoch seconds within C4-THERM's 900s gate",
    type(stamp) == "number" and stamp > now - 900 and stamp <= now,
    stamp
  )
end

T.finish()
