-- Tests that a non-finite MQTT payload is rejected at the two entities that
-- coerce one, by driving _processValue with the payload string a broker would
-- deliver and reading what reaches C4.
--
-- Run from the driver root:
--   make test
-- or:
--   ./test/run_test.sh test_nonfinite_entities.lua
--
-- The payloads here are strings rather than 0/0 because that is the form the
-- bug takes: a failed one-wire or I2C probe on ESPHome and Tasmota firmware
-- publishes the literal text "nan", and tonumber parses "nan", "inf" and an
-- overflowing literal like 1e999 into real non-finite numbers, so the nil
-- guards these call sites already had never fired for them.
--
-- Regression test for DRV-122.

local T = require("testlib")

require("c4_shim")
require("lib.utils")

local bindings = require("lib.bindings")
local MqttSensor = require("mqtt.entities.sensor")
local MqttVariable = require("mqtt.entities.variable")

local BINDING_ID = 7311
local NONFINITE = { "nan", "NaN", "-nan", "inf", "-inf", "INF", "infinity", "1e999", "-1e999" }

--- Feed a payload to a sensor and return what changed and what reached C4.
---
--- Captured at C4.SendToProxy rather than the global SendToProxy of the same
--- name: the global is a wrapper in lib/utils.lua that forwards through C4Call,
--- so stubbing it would measure the argument the entity passed instead of what
--- came out the far end of the path the driver actually takes.
local function feed(sensor, payload)
  local captured = {}
  local realSend = C4.SendToProxy
  local realBinding = bindings.getDynamicBinding
  C4.SendToProxy = function(_, idBinding, strCommand, tParams)
    table.insert(captured, { idBinding = idBinding, command = strCommand, params = tParams })
  end
  bindings.getDynamicBinding = function()
    return { bindingId = BINDING_ID }
  end
  local ok, changedOrErr = pcall(function()
    return sensor:_processValue(payload, payload)
  end)
  C4.SendToProxy = realSend
  bindings.getDynamicBinding = realBinding
  if not ok then
    error(changedOrErr, 0)
  end
  return changedOrErr, captured
end

local function newSensor(name, itemType)
  return MqttSensor:new({ id = name, name = name, itemType = itemType }, 1)
end

--------------------------------------------------------------------------------
T.section("a temperature sensor reports a finite reading")
--------------------------------------------------------------------------------

-- The positive control for every rejection below: it fixes what a reading that
-- is meant to get through looks like on the far side.
local temp = newSensor("Probe Temperature", "TEMPERATURE")

local changed, sent = feed(temp, "21.5")
T.check("the first reading is a change", changed == true)
T.eq("one command reaches C4", #sent, 1)
T.eq("it is a VALUE_CHANGED on the sensor binding", sent[1].command, "VALUE_CHANGED")
T.eq("VALUE carries the reading", sent[1].params.VALUE, 21.5)
T.eq("CELSIUS carries it too", sent[1].params.CELSIUS, 21.5)
T.eq("the cached state is the reading", temp:getValue(), 21.5)
T.eq("the C4 variable holds the reading", Variables["Probe Temperature"], "21.5")

--------------------------------------------------------------------------------
T.section("a non-finite reading is dropped and the last good one stands")
--------------------------------------------------------------------------------

for _, payload in ipairs(NONFINITE) do
  local rejected, alsoSent = feed(temp, payload)
  T.check(string.format("%q is not reported as a change", payload), rejected == false)
  T.eq(string.format("%q sends nothing to the binding", payload), #alsoSent, 0)
  T.eq(string.format("%q leaves the cached state alone", payload), temp:getValue(), 21.5)
  T.eq(string.format("%q leaves the C4 variable alone", payload), Variables["Probe Temperature"], "21.5")
end

--------------------------------------------------------------------------------
T.section("a repeated non-finite reading does not churn")
--------------------------------------------------------------------------------

-- The consequence that made this worth fixing rather than tolerating: NaN never
-- equals itself, so `self._state ~= numValue` was true on every redelivery. A
-- retained message republished by the broker logged and re-notified the proxy
-- forever, at whatever rate the device published.
local churn = newSensor("Churn Temperature", "TEMPERATURE")
local firstChanged = feed(churn, "nan")
local secondChanged, secondSent = feed(churn, "nan")
T.check("the first nan is not a change", firstChanged == false)
T.check("nor is the second", secondChanged == false)
T.eq("and the second sends nothing", #secondSent, 0)
T.eq("nothing was cached to compare against", churn:getValue(), nil)

--------------------------------------------------------------------------------
T.section("the guard does not block readings it should pass")
--------------------------------------------------------------------------------

changed, sent = feed(temp, "22.5")
T.check("a later finite reading is still a change", changed == true)
T.eq("and still reaches the binding", Select(sent, 1, "params", "VALUE"), 22.5)
T.eq("and still updates the C4 variable", Variables["Probe Temperature"], "22.5")

changed, sent = feed(temp, "0")
T.check("a genuine zero is a change", changed == true)
T.eq("zero is not confused with a rejection", Select(sent, 1, "params", "VALUE"), 0)

changed, sent = feed(temp, "-40")
T.check("a negative reading is a change", changed == true)
T.eq("and reaches the binding", Select(sent, 1, "params", "VALUE"), -40)

--------------------------------------------------------------------------------
T.section("a non-numeric payload is still rejected the way it always was")
--------------------------------------------------------------------------------

local rejected, nothing = feed(temp, "warm")
T.check("text is not a change", rejected == false)
T.eq("text sends nothing", #nothing, 0)
T.eq("text leaves the last good reading in place", temp:getValue(), -40)

--------------------------------------------------------------------------------
T.section("the humidity path is guarded too")
--------------------------------------------------------------------------------

local humidity = newSensor("Probe Humidity", "HUMIDITY")

changed, sent = feed(humidity, "48")
T.check("a finite humidity is a change", changed == true)
T.eq("it reaches the binding as a percentage", Select(sent, 1, "params", "SCALE"), "PERCENT")

rejected, nothing = feed(humidity, "inf")
T.check("an infinite humidity is not a change", rejected == false)
T.eq("and sends nothing", #nothing, 0)
T.eq("and leaves the last good reading in place", humidity:getValue(), 48)

--------------------------------------------------------------------------------
T.section("a numeric variable rejects a non-finite payload")
--------------------------------------------------------------------------------

-- Values:update coerces a FLOAT or NUMBER with tonumber, so an unguarded "nan"
-- became a C4 variable holding the string "nan". Every Composer comparison
-- bound to that variable is then operating on a non-number.
for _, varType in ipairs({ "FLOAT", "NUMBER" }) do
  local name = "Setpoint " .. varType
  local variable = MqttVariable:new({ id = name, name = name, itemType = varType }, 1)

  T.check("a finite payload is a change", variable:_processValue("19", "19") == true)
  T.eq(varType .. " holds the payload", Variables[name], "19")

  for _, payload in ipairs(NONFINITE) do
    local accepted = variable:_processValue(payload, payload)
    T.check(string.format("%s rejects %q", varType, payload), accepted == false)
    T.eq(string.format("%s keeps its last good value past %q", varType, payload), Variables[name], "19")
  end

  T.check("a later finite payload is still a change", variable:_processValue("20.5", "20.5") == true)
  T.eq(varType .. " holds the later payload", Variables[name], "20.5")
end

--------------------------------------------------------------------------------
T.section("the guard is scoped to the numeric variable types")
--------------------------------------------------------------------------------

-- The negative control for the section above. "nan" is a legitimate STRING
-- payload, so a guard that fired on the value rather than on the declared type
-- would silently drop it.
local text = MqttVariable:new({ id = "Mode Text", name = "Mode Text", itemType = "STRING" }, 1)
T.check("a STRING variable accepts nan", text:_processValue("nan", "nan") == true)
T.eq("and stores it verbatim", Variables["Mode Text"], "nan")
T.check("a STRING variable accepts inf", text:_processValue("inf", "inf") == true)
T.eq("and stores that verbatim too", Variables["Mode Text"], "inf")

local flag = MqttVariable:new({ id = "Mode Flag", name = "Mode Flag", itemType = "BOOL" }, 1)
T.check("a BOOL variable still accepts a truthy payload", flag:_processValue("on", "on") == true)
T.eq("and coerces it", Variables["Mode Flag"], "1")
T.check("a BOOL variable still accepts nan", flag:_processValue("nan", "nan") == true)
T.eq("and coerces it to false", Variables["Mode Flag"], "0")

T.finish()
