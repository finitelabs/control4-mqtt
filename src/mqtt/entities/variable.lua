--- MQTT Variable entity.
--- Handles typed variables (STRING, BOOL, NUMBER, FLOAT) with C4 variable integration.
--- @class MqttVariable:MqttEntity
--- @field _state any Current variable value.
--- @field variableType string The C4 variable type.

local log = require("lib.logging")
local values = require("lib.values")
local MqttEntity = require("mqtt.entities.base")

--- Variable type configurations.
--- @type table<string, {c4VarType: string, defaultValue: string}>
local VARIABLE_TYPES = {
  STRING = { c4VarType = "STRING", defaultValue = "" },
  BOOL = { c4VarType = "BOOL", defaultValue = "false" },
  NUMBER = { c4VarType = "NUMBER", defaultValue = "0" },
  FLOAT = { c4VarType = "FLOAT", defaultValue = "0" },
}

local MqttVariable = setmetatable({
  TYPE = "VARIABLE",
  BINDING_CLASS = nil, -- Variables don't have bindings
  BINDING_TYPE = nil,
  BINDINGS_NAMESPACE = "MqttVariable",
}, { __index = MqttEntity })

--- Create a new variable entity instance.
--- @param item table The item configuration.
--- @param brokerBinding number The broker binding ID.
--- @return MqttVariable
function MqttVariable:new(item, brokerBinding)
  local instance = MqttEntity.new(self, item, brokerBinding)
  setmetatable(instance, self)
  self.__index = self

  -- Store the variable type info
  local typeInfo = VARIABLE_TYPES[item.itemType]
  if typeInfo then
    instance.variableType = typeInfo.c4VarType
    instance.defaultValue = typeInfo.defaultValue
  end

  return instance
end

--- Get the C4 variable type for this variable.
--- @return string|nil
function MqttVariable:getVariableType()
  return self.variableType
end

--- Get the default value for this variable type.
--- @return string
function MqttVariable:getDefaultValue()
  return self.defaultValue or ""
end

--- Process the extracted value and update the variable.
--- @param value string The extracted value.
--- @param rawPayload string The original raw payload.
--- @return boolean changed Whether the value changed.
function MqttVariable:_processValue(value, rawPayload)
  local changed = self._state ~= value
  self._state = value

  if not changed then
    return false
  end

  -- Update C4 variable
  if self.variableType then
    values:update(self:getName(), value, self.variableType)
  end

  log:info("Variable '%s' updated: %s", self:getName(), value)
  return true
end

--- Publish the variable value to MQTT.
--- @param value any The value to publish.
function MqttVariable:publishValue(value)
  if IsEmpty(self.item.commandTopic) then
    log:debug("No command topic configured for variable '%s'", self:getName())
    return
  end

  log:info("Publishing variable '%s' value: %s -> %s", self:getName(), self.item.commandTopic, value)
  self:publish(self.item.commandTopic, tostring(value))
end

--- Create the variable change callback for C4 variable updates.
--- @return function callback The callback function.
function MqttVariable:createVariableCallback()
  local entity = self
  return function(newValue)
    log:trace("Variable callback for '%s': %s", entity:getName(), newValue)
    entity:publishValue(newValue)
  end
end

--- Register the C4 variable with an optional initial value.
--- @param initialValue any|nil Initial value (uses default if nil).
function MqttVariable:registerVariable(initialValue)
  if not self.variableType then
    log:warn("Cannot register variable '%s' - unknown type", self:getName())
    return
  end

  local value = initialValue or self.defaultValue
  values:update(self:getName(), value, self.variableType, self:createVariableCallback())
  log:debug("Registered variable '%s' (type=%s, value=%s)", self:getName(), self.variableType, value)
end

--- Delete the C4 variable.
function MqttVariable:deleteVariable()
  values:delete(self:getName())
  log:debug("Deleted variable '%s'", self:getName())
end

--- Variables don't have bindings.
--- @return nil
function MqttVariable:registerBinding()
  return nil
end

--- Variables don't have bindings.
function MqttVariable:unregisterBinding()
  -- No-op
end

--- Check if this is a supported variable type.
--- @param itemType string The item type to check.
--- @return boolean
function MqttVariable.isVariableType(itemType)
  return VARIABLE_TYPES[itemType] ~= nil
end

return MqttVariable
