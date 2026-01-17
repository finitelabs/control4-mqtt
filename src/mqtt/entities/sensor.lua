--- MQTT Sensor entity.
--- Handles TEMPERATURE and HUMIDITY sensors with C4 sensor bindings.
--- @class MqttSensor:MqttEntity
--- @field _state number|nil Current sensor value.
--- @field sensorType string The sensor type (TEMPERATURE or HUMIDITY).

local log = require("lib.logging")
local bindings = require("lib.bindings")
local values = require("lib.values")
local MqttEntity = require("mqtt.entities.base")

--- Sensor type configurations.
--- @type table<string, {bindingClass: string, scale: string, c4VarType: string}>
local SENSOR_TYPES = {
  TEMPERATURE = {
    bindingClass = "TEMPERATURE_VALUE",
    c4VarType = "FLOAT",
  },
  HUMIDITY = {
    bindingClass = "HUMIDITY_VALUE",
    scale = "PERCENT",
    c4VarType = "FLOAT",
  },
}

local MqttSensor = setmetatable({
  TYPE = "SENSOR",
  BINDING_TYPE = "CONTROL",
  BINDINGS_NAMESPACE = "MqttSensor",
}, { __index = MqttEntity })

--- Create a new sensor entity instance.
--- @param item table The item configuration.
--- @param brokerBinding number The broker binding ID.
--- @return MqttSensor
function MqttSensor:new(item, brokerBinding)
  local instance = MqttEntity.new(self, item, brokerBinding)
  setmetatable(instance, self)
  self.__index = self

  -- Store sensor type info
  local typeInfo = SENSOR_TYPES[item.itemType]
  if typeInfo then
    instance.sensorType = item.itemType
    instance.bindingClass = typeInfo.bindingClass
    instance.c4VarType = typeInfo.c4VarType
  end

  return instance
end

--- Get the binding key for this sensor.
--- @return string
function MqttSensor:getBindingKey()
  return "item_" .. self:getId()
end

--- Get the current sensor value.
--- @return number|nil
function MqttSensor:getValue()
  return self._state
end

--- Get the temperature scale for this sensor.
--- @return string scale "CELSIUS" or "FAHRENHEIT".
function MqttSensor:getTemperatureScale()
  local scale = self.item.temperatureScale or "Celsius"
  return scale == "Fahrenheit" and "FAHRENHEIT" or "CELSIUS"
end

--- Process the extracted value and update the sensor.
--- @param value string The extracted value.
--- @param rawPayload string The original raw payload.
--- @return boolean changed Whether the value changed.
function MqttSensor:_processValue(value, rawPayload)
  local numValue = tonumber(value)
  if numValue == nil then
    log:warn("Invalid sensor value for '%s': %s", self:getName(), value)
    return false
  end

  local changed = self._state ~= numValue
  self._state = numValue

  -- Update C4 variable
  values:update(self:getName(), value, self.c4VarType or "FLOAT")

  -- Send to binding
  self:sendValue(numValue)

  if changed then
    log:info("Sensor '%s' value: %s", self:getName(), numValue)
  end

  return changed
end

--- Send the sensor value to bound consumers.
--- @param value number|nil The value to send (uses cached value if nil).
function MqttSensor:sendValue(value)
  value = value or self._state
  if value == nil then
    return
  end

  local binding = bindings:getDynamicBinding(self.BINDINGS_NAMESPACE, self:getBindingKey())
  if binding == nil then
    return
  end

  local params = { VALUE = value }

  if self.sensorType == "TEMPERATURE" then
    params.SCALE = self:getTemperatureScale()
    log:debug("Sending temperature value: %s %s to binding %s", value, params.SCALE, binding.bindingId)
  elseif self.sensorType == "HUMIDITY" then
    params.SCALE = "PERCENT"
    log:debug("Sending humidity value: %s to binding %s", value, binding.bindingId)
  end

  SendToProxy(binding.bindingId, "VALUE_CHANGED", params)
end

--- Register the sensor binding and handlers.
--- @return table|nil binding The created binding or nil on failure.
function MqttSensor:registerBinding()
  if not self.bindingClass then
    log:warn("Cannot register binding for sensor '%s' - unknown type", self:getName())
    return nil
  end

  local binding = bindings:getOrAddDynamicBinding(
    self.BINDINGS_NAMESPACE,
    self:getBindingKey(),
    self.BINDING_TYPE,
    true, -- provider
    self:getName(),
    self.bindingClass
  )

  if binding == nil then
    log:error("Failed to create binding for sensor '%s'", self:getName())
    return nil
  end

  log:info("Registered %s binding for '%s' (bindingId=%s)", self.bindingClass, self:getName(), binding.bindingId)

  -- Register RFP handler for value requests
  local entity = self
  RFP[binding.bindingId] = function(idBinding, strCommand, tParams, _args)
    log:debug("RFP[%s] strCommand=%s tParams=%s", idBinding, strCommand, tParams)
    if strCommand == "GET_VALUE" then
      entity:sendValue()
    else
      log:warn("Unhandled command from sensor binding %s: %s", idBinding, strCommand)
    end
  end

  -- Register OBC handler for binding changes
  OBC[binding.bindingId] = function(idBinding, _strClass, bIsBound, otherDeviceId, _otherBindingId)
    log:debug("OBC[%s] bIsBound=%s otherDeviceId=%s", idBinding, bIsBound, otherDeviceId)
    if bIsBound then
      entity:sendValue()
    end
  end

  return binding
end

--- Unregister the sensor binding.
function MqttSensor:unregisterBinding()
  bindings:deleteBinding(self.BINDINGS_NAMESPACE, self:getBindingKey())
  log:debug("Unregistered binding for sensor '%s'", self:getName())
end

--- Check if this is a supported sensor type.
--- @param itemType string The item type to check.
--- @return boolean
function MqttSensor.isSensorType(itemType)
  return SENSOR_TYPES[itemType] ~= nil
end

return MqttSensor
