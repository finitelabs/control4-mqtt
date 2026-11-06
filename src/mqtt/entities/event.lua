--- MQTT Event entity.
--- Handles incoming MQTT events and triggers Control4 buttons/keypads.
--- Creates a BUTTON_LINK binding as a consumer that sends DO_PUSH then DO_CLICK to connected devices.
--- Compatible with Home Assistant MQTT Event integration.
--- @class MqttEvent:MqttEntity
--- @field _state string|nil The last event type received.

local log = require("lib.logging")
local bindings = require("lib.bindings")
local events = require("lib.events")
local values = require("lib.values")
local MqttEntity = require("mqtt.entities.base")

local MqttEvent = setmetatable({
  TYPE = "EVENT",
  BINDING_CLASS = "BUTTON_LINK",
  BINDING_TYPE = "CONTROL",
  BINDINGS_NAMESPACE = "MqttEvent",
  EVENTS_NAMESPACE = "MqttEvent",
}, { __index = MqttEntity })
MqttEvent.__index = MqttEvent

--- Create a new event entity instance.
--- @param item table The item configuration.
--- @param brokerBinding number The broker binding ID.
--- @return MqttEvent instance A new event entity.
function MqttEvent:new(item, brokerBinding)
  return MqttEntity.new(self, item, brokerBinding)
end

--- Get the binding key for this event.
--- @return string key The binding key.
function MqttEvent:getBindingKey()
  return "event_" .. self:getId()
end

--- Get the event key for this event.
--- @return string key The event key.
function MqttEvent:getEventKey()
  return "event_" .. self:getId()
end

--- Get the event name for display.
--- @return string name The event's name.
function MqttEvent:getEventName()
  return self:getName() .. " Triggered"
end

--- Get the event type filter (comma-separated list of accepted event types).
--- @return string|nil filter The filter, or nil.
function MqttEvent:getEventTypeFilter()
  return self.item.eventTypeFilter
end

--- Check if an event type passes the filter.
--- @param eventType string The event type to check.
--- @return boolean passes True if the event type passes the filter.
function MqttEvent:passesFilter(eventType)
  local filter = self:getEventTypeFilter()
  if IsEmpty(filter) then
    return true -- No filter, accept all
  end

  -- Parse comma-separated filter values
  for value in string.gmatch(filter, "[^,]+") do
    local trimmed = value:match("^%s*(.-)%s*$") -- Trim whitespace
    if trimmed == eventType then
      return true
    end
  end

  return false
end

--- Get the current state (last event type).
--- @return string|nil eventType The last event type, or nil.
function MqttEvent:getState()
  return self._state
end

--- Get state as display text.
--- @return string text The last event type, or empty.
function MqttEvent:getStateText()
  return self._state or ""
end

--- The item's state variable.
--- @return string[] names The variable names.
function MqttEvent:getVariableNames()
  return { self:getStateVarName() }
end

--- Create the state variable, empty, unless it exists.
function MqttEvent:seedVariables()
  self:_seedVariable(self:getStateVarName(), "STRING")
end

--- Process the extracted value and trigger event/binding.
--- @param value string The extracted value (event type).
--- @param _rawPayload string The original raw payload.
--- @param retained boolean|nil Whether this is a stored message rather than one just published.
--- @return boolean changed Whether the state changed.
function MqttEvent:_processValue(value, _rawPayload, retained)
  local eventType = tostring(value)

  if retained then
    log:debug("Event '%s' - ignored a stored message: %s", self:getName(), eventType)
    return false
  end

  if not self:passesFilter(eventType) then
    log:debug("Event '%s' - filtered out event type: %s", self:getName(), eventType)
    return false
  end

  self._state = eventType
  values:update(self:getStateVarName(), eventType, "STRING")
  events:fire(self.EVENTS_NAMESPACE, self:getEventKey())
  log:info("Event '%s' triggered: %s", self:getName(), eventType)

  -- Send DO_PUSH then DO_CLICK to bound devices
  self:_sendButtonPress()

  return true
end

--- Send button press commands to devices bound to this event's BUTTON_LINK binding.
function MqttEvent:_sendButtonPress()
  local binding = bindings:getDynamicBinding(self.BINDINGS_NAMESPACE, self:getBindingKey())
  if binding == nil then
    log:debug("Event '%s' - no binding registered", self:getName())
    return
  end

  -- What a Control4 keypad emits for a tap. DO_CLICK and DO_RELEASE are the two
  -- mutually exclusive terminations of a press: a bound load reads DO_RELEASE as
  -- the end of a hold, so it must not follow.
  log:debug("Sending DO_PUSH then DO_CLICK from binding %s", binding.bindingId)
  SendToProxy(binding.bindingId, "DO_PUSH", {}, "COMMAND")
  SendToProxy(binding.bindingId, "DO_CLICK", {}, "COMMAND")
end

--- Register the BUTTON_LINK binding (consumer) and Control4 event.
--- @return table|nil binding The created binding or nil on failure.
function MqttEvent:registerBinding()
  -- Create BUTTON_LINK binding as consumer (provider=false)
  local binding = bindings:getOrAddDynamicBinding(
    self.BINDINGS_NAMESPACE,
    self:getBindingKey(),
    self.BINDING_TYPE,
    false, -- consumer (not provider)
    self:getName(),
    self.BINDING_CLASS
  )

  if binding == nil then
    log:error("Failed to create BUTTON_LINK binding for event '%s'", self:getName())
    return nil
  end

  log:info("Registered BUTTON_LINK binding (consumer) for '%s' (bindingId=%s)", self:getName(), binding.bindingId)

  local eventName = self:getEventName()
  local eventDescription = "When NAME MQTT event '" .. self:getName() .. "' receives a matching message"
  events:getOrAddEvent(self.EVENTS_NAMESPACE, self:getEventKey(), eventName, eventDescription)
  log:debug("Registered event '%s' for event '%s'", eventName, self:getName())

  return binding
end

--- Unregister the event binding and Control4 event.
function MqttEvent:unregisterBinding()
  bindings:deleteBinding(self.BINDINGS_NAMESPACE, self:getBindingKey())
  log:debug("Unregistered BUTTON_LINK binding for event '%s'", self:getName())

  events:deleteEvent(self.EVENTS_NAMESPACE, self:getEventKey())
  log:debug("Unregistered event for '%s'", self:getName())
end

return MqttEvent
