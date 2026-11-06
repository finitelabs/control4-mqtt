-- What an MQTT variable item shows after programming writes it, by writing the variable the way Director does and
-- driving the entity with MQTT messages.
--
-- Run from the driver root:
--   make test
-- or:
--   ./test/run_test.sh test_variable_report_wins.lua
--
-- A programming write is published to the command topic. The device's next report of its state topic is what the
-- variable shows, whether the device took the write or kept its earlier value.

local T = require("testlib")

require("c4_shim")
require("lib.utils")

local MqttVariable = require("mqtt.entities.variable")

local published = {}
C4.SendToProxy = function(_, _, strCommand, tParams)
  if strCommand == "PUBLISH" then
    table.insert(published, tParams.payload)
  end
end

--- Programming sets the variable: Director changes it, then calls the driver's OnVariableChanged.
local function programmingWrites(name, value)
  C4:SetVariable(name, value)
  OnVariableChanged(name)
end

local function newVariable(name, itemType)
  local variable = MqttVariable:new({
    id = name,
    name = name,
    itemType = itemType,
    stateTopic = "hvac/" .. name,
    commandTopic = "hvac/" .. name .. "/set",
  }, 1)
  variable:registerVariable()
  return variable
end

--------------------------------------------------------------------------------
T.section("a write the device refuses gives way to its report")
--------------------------------------------------------------------------------

do
  local mode = newVariable("Mode", "STRING")
  mode:onMessage("auto")
  programmingWrites("Mode", "eco")
  T.eq("the write is published", published, { "eco" })
  T.eq("and shows until the device answers", Variables["Mode"], "eco")
  mode:onMessage("auto")
  T.eq("the device keeping auto puts auto back", Variables["Mode"], "auto")
end

do
  local setpoint = newVariable("Setpoint", "FLOAT")
  setpoint:onMessage("20")
  programmingWrites("Setpoint", "35")
  setpoint:onMessage("20")
  T.eq("a number too", Variables["Setpoint"], "20")
end

--------------------------------------------------------------------------------
T.section("a write the device takes stays")
--------------------------------------------------------------------------------

do
  local mode = newVariable("Fan", "STRING")
  mode:onMessage("low")
  programmingWrites("Fan", "high")
  T.check("the device's echo is a change", mode:onMessage("high"))
  T.eq("the variable shows it", Variables["Fan"], "high")
  T.check("a repeat is not", not mode:onMessage("high"))
end

T.finish()
