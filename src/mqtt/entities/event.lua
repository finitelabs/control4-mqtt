--- MQTT Event entity.
--- Handles incoming MQTT events and triggers Control4 buttons/keypads.
--- Creates a BUTTON_LINK binding as a consumer that sends DO_CLICK to connected devices.
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

--- Create a new event entity instance.
--- @param item table The item configuration.
--- @param brokerBinding number The broker binding ID.
--- @return MqttEvent
function MqttEvent:new(item, brokerBinding)
  local instance = MqttEntity.new(self, item, brokerBinding)
  setmetatable(instance, self)
  self.__index = self
  return instance
end

--- Get the binding key for this event.
--- @return string
function MqttEvent:getBindingKey()
  return "event_" .. self:getId()
end

--- Get the event key for this event.
--- @return string
function MqttEvent:getEventKey()
  return "event_" .. self:getId()
end

--- Get the event name for display.
--- @return string
function MqttEvent:getEventName()
  return self:getName() .. " Triggered"
end

--- Get the event type filter (comma-separated list of accepted event types).
--- @return string|nil
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
--- @return string|nil
function MqttEvent:getState()
  return self._state
end

--- Get state as display text.
--- @return string
function MqttEvent:getStateText()
  return self._state or ""
end

--- Process the extracted value and trigger event/binding.
--- @param value string The extracted value (event type).
--- @param rawPayload string The original raw payload.
--- @return boolean changed Whether the state changed.
function MqttEvent:_processValue(value, rawPayload)
  local eventType = tostring(value)

  -- Check filter
  if not self:passesFilter(eventType) then
    log:debug("Event '%s' - filtered out event type: %s", self:getName(), eventType)
    return false
  end

  -- Update state
  self._state = eventType

  -- Update C4 variable for programming
  values:update(self:getStateVarName(), eventType, "STRING")

  -- Fire Control4 event
  events:fire(self.EVENTS_NAMESPACE, self:getEventKey())
  log:info("Event '%s' triggered: %s", self:getName(), eventType)

  -- Send DO_CLICK to bound devices
  self:_sendButtonClick()

  return true
end

--- Send button press commands to devices bound to this event's BUTTON_LINK binding.
function MqttEvent:_sendButtonClick()
  local binding = bindings:getDynamicBinding(self.BINDINGS_NAMESPACE, self:getBindingKey())
  if binding == nil then
    log:debug("Event '%s' - no binding registered", self:getName())
    return
  end

  log:debug("Sending DO_CLICK and DO_PUSH/DO_RELEASE from binding %s", binding.bindingId)
  SendToProxy(binding.bindingId, "DO_CLICK", {}, "COMMAND")
  SendToProxy(binding.bindingId, "DO_PUSH", {}, "COMMAND")
  SendToProxy(binding.bindingId, "DO_RELEASE", {}, "COMMAND")
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

  -- Register Control4 event
  local eventName = self:getEventName()
  local eventDescription = "Fires when MQTT event '" .. self:getName() .. "' receives a matching message"
  events:getOrAddEvent(self.EVENTS_NAMESPACE, self:getEventKey(), eventName, eventDescription)
  log:debug("Registered event '%s' for event '%s'", eventName, self:getName())

  return binding
end

--- Unregister the event binding and Control4 event.
function MqttEvent:unregisterBinding()
  -- Delete binding
  bindings:deleteBinding(self.BINDINGS_NAMESPACE, self:getBindingKey())
  log:debug("Unregistered BUTTON_LINK binding for event '%s'", self:getName())

  -- Delete Control4 event
  events:deleteEvent(self.EVENTS_NAMESPACE, self:getEventKey())
  log:debug("Unregistered event for '%s'", self:getName())
end

return MqttEvent
