-- Tests what an MQTT relay item tells its bound relay driver, by driving the
-- binding handlers and reading what reaches C4.SendToProxy.
--
-- Run from the driver root:
--   make test
-- or:
--   ./test/run_test.sh test_relay_state_notify.lua
--
-- A RELAY provider has two ways to report state. CLOSED/OPENED fire the bound
-- relay driver's programming events, so they belong to a real change only.
-- STATE_CLOSED/STATE_OPENED set the same state silently, and are what a bind
-- and a GET_STATE get: neither is a change. Binding used to send the eventful
-- form, so the bound driver's programming ran at every bind and every
-- controller start, and GET_STATE went unanswered.

local T = require("testlib")

require("c4_shim")
require("lib.utils")

local bindings = require("lib.bindings")
local MqttRelay = require("mqtt.entities.relay")

local BROKER_BINDING = 1

--- Every C4.SendToProxy call, captured at the far end of the SendToProxy wrapper
--- in lib/utils.lua so what is measured is what the controller would receive.
local sent = {}
C4.SendToProxy = function(_, idBinding, strCommand, tParams, strMessage)
  table.insert(sent, { idBinding = idBinding, command = strCommand, params = tParams, message = strMessage })
end

local function sentTo(idBinding)
  local out = {}
  for _, call in ipairs(sent) do
    if call.idBinding == idBinding then
      table.insert(out, call)
    end
  end
  return out
end

--- The command of each send to the relay binding, in order.
local function relayCommands(relayBinding)
  local out = {}
  for _, call in ipairs(sentTo(relayBinding)) do
    table.insert(out, call.command)
  end
  return out
end

--- The payload of each PUBLISH to the broker, in order.
local function published()
  local out = {}
  for _, call in ipairs(sentTo(BROKER_BINDING)) do
    if call.command == "PUBLISH" then
      table.insert(out, call.params.payload)
    end
  end
  return out
end

--- A fresh relay with its binding registered and nothing yet sent.
local function newRelay(overrides)
  bindings:reset()
  ShimResetDynamicBindings()
  local item = {
    id = "r1",
    name = "Pump",
    stateTopic = "pump/state",
    commandTopic = "pump/set",
    stateOn = "ON",
    stateOff = "OFF",
    optimistic = "No",
  }
  for k, v in pairs(overrides or {}) do
    item[k] = v
  end
  local relay = MqttRelay:new(item, BROKER_BINDING)
  local binding = relay:registerBinding()
  sent = {}
  return relay, binding.bindingId
end

local function bind(bindingId)
  OnBindingChanged(bindingId, "RELAY", true, 900, 1)
end

local function unbind(bindingId)
  OnBindingChanged(bindingId, "RELAY", false, 900, 1)
end

local function command(bindingId, strCommand, tParams)
  ReceivedFromProxy(bindingId, strCommand, tParams or {})
end

--------------------------------------------------------------------------------
T.section("binding reports a known state silently")
--------------------------------------------------------------------------------

do
  local relay, id = newRelay()
  relay:onMessage("ON")
  sent = {}
  bind(id)
  T.eq("an on relay sends STATE_CLOSED, not CLOSED", relayCommands(id), { "STATE_CLOSED" })
  T.eq("as a NOTIFY", sentTo(id)[1] and sentTo(id)[1].message, "NOTIFY")
end

do
  local relay, id = newRelay()
  relay:onMessage("OFF")
  sent = {}
  bind(id)
  T.eq("an off relay sends STATE_OPENED, not OPENED", relayCommands(id), { "STATE_OPENED" })
end

do
  local _, id = newRelay()
  bind(id)
  T.eq("an unknown state sends nothing", relayCommands(id), {})
end

do
  local relay, id = newRelay()
  relay:onMessage("ON")
  sent = {}
  unbind(id)
  T.eq("unbinding sends nothing", relayCommands(id), {})
end

--------------------------------------------------------------------------------
T.section("GET_STATE is answered silently from the known state")
--------------------------------------------------------------------------------

do
  local relay, id = newRelay()
  relay:onMessage("ON")
  sent = {}
  command(id, "GET_STATE")
  T.eq("an on relay answers STATE_CLOSED", relayCommands(id), { "STATE_CLOSED" })
  T.eq("as a NOTIFY", sentTo(id)[1] and sentTo(id)[1].message, "NOTIFY")
  T.eq("and publishes nothing", published(), {})
end

do
  local relay, id = newRelay()
  relay:onMessage("OFF")
  sent = {}
  command(id, "GET_STATE")
  T.eq("an off relay answers STATE_OPENED", relayCommands(id), { "STATE_OPENED" })
end

do
  local _, id = newRelay()
  command(id, "GET_STATE")
  T.eq("an unknown state answers nothing", relayCommands(id), {})
  T.eq("and publishes nothing", published(), {})
end

do
  local relay, id = newRelay()
  relay:onMessage("ON")
  sent = {}
  command(id, "SOMETHING_ELSE")
  T.eq("another unknown command is still ignored", #sent, 0)
end

--------------------------------------------------------------------------------
T.section("a real change from MQTT still fires programming")
--------------------------------------------------------------------------------

do
  local relay, id = newRelay()
  relay:onMessage("ON")
  relay:onMessage("OFF")
  relay:onMessage("OFF")
  relay:onMessage("ON")
  T.eq(
    "each change sends CLOSED or OPENED, a repeat sends nothing",
    relayCommands(id),
    { "CLOSED", "OPENED", "CLOSED" }
  )
end

do
  local relay, id = newRelay({ optimistic = "Yes" })
  command(id, "ON")
  T.eq("an optimistic command is a change and sends CLOSED", relayCommands(id), { "CLOSED" })
  T.eq("the state is now on", relay:getState(), true)
end

--------------------------------------------------------------------------------
T.section("commands from Control4 publish as before")
--------------------------------------------------------------------------------

do
  local _, id = newRelay()
  command(id, "ON")
  command(id, "CLOSE")
  command(id, "OFF")
  command(id, "OPEN")
  T.eq("ON, CLOSE, OFF and OPEN publish their payloads", published(), { "ON", "ON", "OFF", "OFF" })
  T.eq("and send nothing back until MQTT confirms", relayCommands(id), {})
end

do
  local relay, id = newRelay()
  relay:onMessage("ON")
  sent = {}
  command(id, "TOGGLE")
  T.eq("TOGGLE from on publishes OFF", published(), { "OFF" })
end

do
  local relay, id = newRelay()
  relay:onMessage("OFF")
  sent = {}
  command(id, "TOGGLE")
  T.eq("TOGGLE from off publishes ON", published(), { "ON" })
end

do
  local _, id = newRelay()
  command(id, "TOGGLE")
  T.eq("TOGGLE with no known state publishes ON", published(), { "ON" })
end

do
  local _, id = newRelay()
  command(id, "TRIGGER", { TIME = "500" })
  T.eq("TRIGGER publishes ON", published(), { "ON" })
  ShimFireTimers()
  T.eq("then OFF once the pulse ends", published(), { "ON", "OFF" })
end

do
  local _, id = newRelay()
  command(id, "TRIGGER", {})
  ShimFireTimers()
  T.eq("TRIGGER with no TIME publishes ON only", published(), { "ON" })
end

do
  local _, id = newRelay({ payloadOn = "1", payloadOff = "0" })
  command(id, "ON")
  command(id, "OFF")
  T.eq("custom payloads are published", published(), { "1", "0" })
end

T.finish()
