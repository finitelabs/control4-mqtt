--- MQTT Contact sensor entity.
--- Handles open/closed state and contact sensor binding notifications.
--- @class MqttContact:MqttEntity
--- @field _state boolean|nil Current contact state (true = open, false = closed).

local log = require("lib.logging")
local bindings = require("lib.bindings")
local values = require("lib.values")
local stateParser = require("mqtt.state_parser")
local MqttEntity = require("mqtt.entities.base")

local MqttContact = setmetatable({
  TYPE = "CONTACT",
  BINDING_CLASS = "CONTACT_SENSOR",
  BINDING_TYPE = "PROXY",
  BINDINGS_NAMESPACE = "MqttContact",
}, { __index = MqttEntity })

--- Create a new contact entity instance.
--- @param item table The item configuration.
--- @param brokerBinding number The broker binding ID.
--- @return MqttContact
function MqttContact:new(item, brokerBinding)
  local instance = MqttEntity.new(self, item, brokerBinding)
  setmetatable(instance, self)
  self.__index = self
  return instance
end

--- Get the binding key for this contact.
--- @return string
function MqttContact:getBindingKey()
  return "item_" .. self:getId()
end

--- Parse contact state from payload using "match one, default other" logic.
--- @param value string The payload value.
--- @return boolean|nil
function MqttContact:parseState(value)
  local stateOpen = self.item.stateOpen or ""
  local stateClosed = self.item.stateClosed or ""
  return stateParser.parse(value, stateOpen, stateClosed)
end

--- Get the current contact state.
--- @return boolean|nil state True = open, false = closed, nil = unknown.
function MqttContact:getState()
  return self._state
end

--- Get state as display text.
--- @return string
function MqttContact:getStateText()
  if self._state == nil then
    return ""
  end
  return self._state and "Open" or "Closed"
end

--- Process the extracted value and update state.
--- @param value string The extracted value.
--- @param rawPayload string The original raw payload.
--- @return boolean changed Whether the state changed.
function MqttContact:_processValue(value, rawPayload)
  local isOpen = self:parseState(value)
  if isOpen == nil then
    log:debug("Contact '%s' - could not parse state from: %s", self:getName(), value)
    return false
  end

  return self:_updateState(isOpen, rawPayload)
end

--- Update the contact state and notify binding.
--- @param isOpen boolean The new state (true = open).
--- @param payload string|nil The raw payload (for display).
--- @return boolean changed Whether the state changed.
function MqttContact:_updateState(isOpen, payload)
  local changed = self._state ~= isOpen
  self._state = isOpen

  if not changed then
    return false
  end

  local stateText = self:getStateText()

  -- Update C4 variable for programming
  values:update(self:getStateVarName(), stateText, "STRING")

  -- Notify binding
  local binding = bindings:getDynamicBinding(self.BINDINGS_NAMESPACE, self:getBindingKey())
  if binding then
    local bindingState = isOpen and "OPENED" or "CLOSED"
    log:debug("Sending contact state %s to binding %s", bindingState, binding.bindingId)
    SendToProxy(binding.bindingId, bindingState, {}, "NOTIFY")
  end

  log:info("Contact '%s' state: %s", self:getName(), stateText)
  return true
end

--- Register the contact binding and OBC handler.
--- @return table|nil binding The created binding or nil on failure.
function MqttContact:registerBinding()
  local binding = bindings:getOrAddDynamicBinding(
    self.BINDINGS_NAMESPACE,
    self:getBindingKey(),
    self.BINDING_TYPE,
    true, -- provider
    self:getName(),
    self.BINDING_CLASS
  )

  if binding == nil then
    log:error("Failed to create binding for contact '%s'", self:getName())
    return nil
  end

  log:info("Registered CONTACT_SENSOR binding for '%s' (bindingId=%s)", self:getName(), binding.bindingId)

  -- Contact sensors are read-only, no RFP handler needed
  -- Register OBC handler for binding changes
  local entity = self
  OBC[binding.bindingId] = function(idBinding, strClass, bIsBound, otherDeviceId, otherBindingId)
    log:debug("OBC[%s] bIsBound=%s otherDeviceId=%s", idBinding, bIsBound, otherDeviceId)
    -- Preserve connection info for restore
    bindings:onBindingChanged(
      entity.BINDINGS_NAMESPACE,
      entity:getBindingKey(),
      idBinding,
      strClass,
      bIsBound,
      otherDeviceId,
      otherBindingId
    )
    -- Send current state to newly bound device
    if bIsBound and entity._state ~= nil then
      local bindingState = entity._state and "OPENED" or "CLOSED"
      SendToProxy(binding.bindingId, bindingState, {}, "NOTIFY")
    end
  end

  return binding
end

--- Unregister the contact binding.
function MqttContact:unregisterBinding()
  bindings:deleteBinding(self.BINDINGS_NAMESPACE, self:getBindingKey())
  log:debug("Unregistered binding for contact '%s'", self:getName())
end

return MqttContact
