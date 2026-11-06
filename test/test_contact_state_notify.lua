-- Tests what an MQTT contact item tells its bound contact driver, by driving the binding handlers and reading what
-- reaches C4.SendToProxy.
--
-- Run from the driver root:
--   make test
-- or:
--   ./test/run_test.sh test_contact_state_notify.lua
--
-- A CONTACT_SENSOR provider has two ways to report state. OPENED/CLOSED fire the bound contact driver's
-- programming events, even when its state is unchanged, so they belong to a real change only.
-- STATE_OPENED/STATE_CLOSED set the same state silently, and are what a bind and the first state heard from MQTT
-- get: neither is a change.

local T = require("testlib")

require("c4_shim")
require("lib.utils")

local bindings = require("lib.bindings")
local MqttContact = require("mqtt.entities.contact")

--- Every C4.SendToProxy call, captured at the far end of the SendToProxy wrapper in lib/utils.lua.
local sent = {}
C4.SendToProxy = function(_, idBinding, strCommand, tParams, strMessage)
  table.insert(sent, { idBinding = idBinding, command = strCommand, params = tParams, message = strMessage })
end

--- The command of each send to the contact binding, in order.
local function contactCommands(contactBinding)
  local out = {}
  for _, call in ipairs(sent) do
    if call.idBinding == contactBinding then
      table.insert(out, call.command)
    end
  end
  return out
end

--- A fresh contact with its binding registered and nothing yet sent.
local function newContact()
  bindings:reset()
  ShimResetDynamicBindings()
  local contact = MqttContact:new({
    id = "c1",
    name = "Front Door",
    stateTopic = "door/contact",
    stateOpen = "open",
    stateClosed = "closed",
  }, 1)
  local binding = contact:registerBinding()
  sent = {}
  return contact, binding.bindingId
end

local function bind(bindingId)
  OnBindingChanged(bindingId, "CONTACT_SENSOR", true, 900, 1)
end

--------------------------------------------------------------------------------
T.section("binding reports a known state silently")
--------------------------------------------------------------------------------

do
  local contact, id = newContact()
  contact:onMessage("open")
  sent = {}
  bind(id)
  T.eq("an open contact sends STATE_OPENED, not OPENED", contactCommands(id), { "STATE_OPENED" })
  T.eq("as a NOTIFY", sent[1] and sent[1].message, "NOTIFY")
end

do
  local contact, id = newContact()
  contact:onMessage("closed")
  sent = {}
  bind(id)
  T.eq("a closed contact sends STATE_CLOSED, not CLOSED", contactCommands(id), { "STATE_CLOSED" })
end

do
  local _, id = newContact()
  bind(id)
  T.eq("an unknown state sends nothing", contactCommands(id), {})
end

--------------------------------------------------------------------------------
T.section("the first state heard is what the contact already was")
--------------------------------------------------------------------------------

do
  local contact, id = newContact()
  bind(id)
  contact:onMessage("open")
  T.eq("the first state after a start is sent as STATE_OPENED", contactCommands(id), { "STATE_OPENED" })
end

do
  local contact, id = newContact()
  bind(id)
  contact:onMessage("closed", true)
  T.eq("a retained first state is sent as STATE_CLOSED", contactCommands(id), { "STATE_CLOSED" })
end

do
  local contact, id = newContact()
  bind(id)
  contact:onMessage("open")
  sent = {}
  contact:reset()
  contact:onMessage("closed")
  T.eq("the first state after a broker rebind is silent too", contactCommands(id), { "STATE_CLOSED" })
end

--------------------------------------------------------------------------------
T.section("a real change fires the bound driver's programming")
--------------------------------------------------------------------------------

do
  local contact, id = newContact()
  bind(id)
  contact:onMessage("closed")
  sent = {}
  contact:onMessage("open")
  T.eq("closed to open sends OPENED", contactCommands(id), { "OPENED" })
  sent = {}
  contact:onMessage("closed")
  T.eq("open to closed sends CLOSED", contactCommands(id), { "CLOSED" })
end

do
  local contact, id = newContact()
  bind(id)
  contact:onMessage("open")
  sent = {}
  contact:onMessage("open")
  T.eq("the same state again sends nothing", contactCommands(id), {})
end

--------------------------------------------------------------------------------
T.section("the first state is checked against the bound contact driver")
--------------------------------------------------------------------------------

--- Bind to a contact driver showing `shown` in its ContactState ("0" open, "1" closed), or nothing readable.
local function bindShowing(bindingId, shown)
  C4:Unbind(900, 1)
  C4:Bind(C4:GetDeviceID(), bindingId, 900, 1, "CONTACT_SENSOR")
  ShimSetDevices({ [900] = { variables = shown and { ["1000"] = { name = "ContactState", value = shown } } or {} } })
  bind(bindingId)
end

do
  local contact, id = newContact()
  bindShowing(id, "1")
  contact:onMessage("closed")
  T.eq("a first state the contact already shows is silent", contactCommands(id), { "STATE_CLOSED" })
end

do
  local contact, id = newContact()
  bindShowing(id, "1")
  contact:onMessage("open", true)
  T.eq("a first state the contact doesn't show is a change: OPENED", contactCommands(id), { "OPENED" })
end

do
  local contact, id = newContact()
  bindShowing(id, "0")
  contact:onMessage("closed")
  T.eq("and the other way round: CLOSED", contactCommands(id), { "CLOSED" })
end

do
  local contact, id = newContact()
  bindShowing(id, nil)
  contact:onMessage("open")
  T.eq("a contact driver with nothing readable gets it silently", contactCommands(id), { "STATE_OPENED" })
end

do
  local contact, id = newContact()
  bindShowing(id, "1")
  sent = {}
  contact:onMessage("closed")
  sent = {}
  contact:onMessage("open")
  T.eq("after the first state, a change is OPENED as before", contactCommands(id), { "OPENED" })
end

ShimResetDevices()
C4:Unbind(900, 1)

T.finish()
