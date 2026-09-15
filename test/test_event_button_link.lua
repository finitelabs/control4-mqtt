-- Tests that an MQTT event drives its BUTTON_LINK binding with what a Control4
-- keypad sends for a tap, by driving MqttEvent:_processValue and reading what
-- reaches C4.
--
-- Run from the driver root:
--   make test
-- or:
--   ./test/run_test.sh test_event_button_link.lua
--
-- DO_CLICK and DO_RELEASE are the two mutually exclusive terminations of one
-- press, and a bound load reads DO_RELEASE as the end of a hold. The old
-- DO_CLICK/DO_PUSH/DO_RELEASE triple therefore started a click, started a hold,
-- then froze the ramp a bound light had just begun.
--
-- Regression test for DRV-120.

local T = require("testlib")

require("c4_shim")
require("lib.utils")

local bindings = require("lib.bindings")
local MqttEvent = require("mqtt.entities.event")

local BINDING_ID = 4242

--- Drive an event with a payload and return every command C4 received, in order.
---
--- Captured at C4.SendToProxy rather than the global SendToProxy of the same
--- name: the global is a wrapper in lib/utils.lua that forwards through C4Call,
--- so stubbing it would measure the argument the entity passed instead of what
--- came out the far end of the path the driver actually takes.
local function triggerAndCapture(item, eventType, bindingId)
  local captured = {}
  local realSend = C4.SendToProxy
  local realBinding = bindings.getDynamicBinding
  C4.SendToProxy = function(_, idBinding, strCommand, tParams, strType)
    table.insert(captured, { idBinding = idBinding, command = strCommand, params = tParams, type = strType })
  end
  bindings.getDynamicBinding = function()
    return bindingId ~= nil and { bindingId = bindingId } or nil
  end
  local ok, err = pcall(function()
    MqttEvent:new(item, 1):_processValue(eventType, eventType)
  end)
  C4.SendToProxy = realSend
  bindings.getDynamicBinding = realBinding
  if not ok then
    error(err, 0)
  end
  return captured
end

local function commandsOf(captured)
  local commands = {}
  for i, call in ipairs(captured) do
    commands[i] = call.command
  end
  return commands
end

--------------------------------------------------------------------------------
T.section("a received event sends the keypad tap sequence")
--------------------------------------------------------------------------------

local tap = triggerAndCapture({ id = "e1", name = "Doorbell" }, "single_press", BINDING_ID)

T.eq("DO_PUSH then DO_CLICK, and nothing else", commandsOf(tap), { "DO_PUSH", "DO_CLICK" })
T.eq("exactly two commands", #tap, 2)
T.eq("DO_PUSH is first", tap[1].command, "DO_PUSH")
T.eq("DO_CLICK terminates the press", tap[2].command, "DO_CLICK")

for i, call in ipairs(tap) do
  T.neq(string.format("command %d is not DO_RELEASE", i), call.command, "DO_RELEASE")
  T.eq(string.format("command %d goes to the button binding", i), call.idBinding, BINDING_ID)
  T.eq(string.format("command %d is sent as a COMMAND", i), call.type, "COMMAND")
  T.eq(string.format("command %d carries no parameters", i), call.params, {})
end

--------------------------------------------------------------------------------
T.section("an event type the filter rejects sends nothing")
--------------------------------------------------------------------------------

-- The negative control for the section above: it proves the captured sequence
-- comes from the button path this file is measuring and not from entity setup.
local filtered =
  triggerAndCapture({ id = "e2", name = "Remote", eventTypeFilter = "single_press" }, "double_press", BINDING_ID)

T.eq("no commands reach C4", commandsOf(filtered), {})

local accepted = triggerAndCapture(
  { id = "e3", name = "Remote", eventTypeFilter = "single_press, double_press" },
  "double_press",
  BINDING_ID
)

T.eq("an accepted type still sends the pair", commandsOf(accepted), { "DO_PUSH", "DO_CLICK" })

--------------------------------------------------------------------------------
T.section("an event with no binding registered sends nothing")
--------------------------------------------------------------------------------

local unbound = triggerAndCapture({ id = "e4", name = "Orphan" }, "single_press", nil)

T.eq("no commands reach C4", commandsOf(unbound), {})

T.finish()
