-- When an MQTT temperature or humidity item tells its bound consumer a reading, by driving the entity with MQTT
-- messages and reading what reaches C4.SendToProxy.
--
-- Run from the driver root:
--   make test
-- or:
--   ./test/run_test.sh test_sensor_value_notify.lua
--
-- A reading goes out when it changes. The first one after a start or a broker rebind goes out even when it equals
-- the last, since a bound thermostat comes back from a controller restart with none.

local T = require("testlib")

require("c4_shim")
require("lib.utils")

local bindings = require("lib.bindings")
local MqttSensor = require("mqtt.entities.sensor")

local sent = {}
C4.SendToProxy = function(_, idBinding, strCommand, tParams, strMessage)
  table.insert(sent, { idBinding = idBinding, command = strCommand, params = tParams, message = strMessage })
end

--- The VALUE of each send, in order.
local function told()
  local out = {}
  for _, call in ipairs(sent) do
    table.insert(out, call.params.VALUE)
  end
  return out
end

--- A fresh sensor with its binding registered and nothing yet sent.
local function newSensor(itemType)
  bindings:reset()
  ShimResetDynamicBindings()
  local sensor = MqttSensor:new({ id = "s1", name = "Probe", itemType = itemType, stateTopic = "probe/state" }, 1)
  sensor:registerBinding()
  sent = {}
  return sensor
end

--------------------------------------------------------------------------------
T.section("a reading goes out when it changes")
--------------------------------------------------------------------------------

do
  local sensor = newSensor("TEMPERATURE")
  sensor:onMessage("21.5")
  sensor:onMessage("21.5")
  sensor:onMessage("21.5")
  T.eq("three equal readings go out once", told(), { 21.5 })
  sensor:onMessage("22")
  T.eq("a new reading goes out", told(), { 21.5, 22 })
  sensor:onMessage("22", true)
  T.eq("re-reading the last message sends nothing", told(), { 21.5, 22 })
  T.eq("as VALUE_CHANGED", sent[1] and sent[1].command, "VALUE_CHANGED")
  T.eq("sent as a NOTIFY", sent[1] and sent[1].message, "NOTIFY")
end

do
  local sensor = newSensor("HUMIDITY")
  sensor:onMessage("48")
  sensor:onMessage("48")
  T.eq("humidity too", told(), { 48 })
  T.eq("as a NOTIFY", sent[1] and sent[1].message, "NOTIFY")
end

--------------------------------------------------------------------------------
T.section("the first reading after a start or a rebind goes out")
--------------------------------------------------------------------------------

do
  local sensor = newSensor("TEMPERATURE")
  sensor:onMessage("21.5")
  sensor:reset()
  sensor:onMessage("21.5", true)
  T.eq("an unchanged reading after a broker rebind goes out again", told(), { 21.5, 21.5 })
end

do
  local restarted = newSensor("TEMPERATURE")
  restarted:onMessage("21.5", true)
  T.eq("after a start, the retained reading goes out", told(), { 21.5 })
end

--------------------------------------------------------------------------------
T.section("a bind and GET_VALUE still get the reading")
--------------------------------------------------------------------------------

do
  local sensor = newSensor("TEMPERATURE")
  sensor:onMessage("21.5")
  local id = bindings:getDynamicBinding("MqttSensor", sensor:getBindingKey()).bindingId
  sent = {}
  OnBindingChanged(id, "TEMPERATURE_VALUE", true, 900, 1)
  ReceivedFromProxy(id, "GET_VALUE", {})
  T.eq("each gets the reading", told(), { 21.5, 21.5 })
end

T.finish()
