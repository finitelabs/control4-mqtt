--- Base class for MQTT entities.
--- Provides common functionality for topic subscription, payload extraction,
--- state caching, and property updates.
--- @class MqttEntity
--- @field TYPE string The entity type identifier (override in subclass).
--- @field item table The item configuration data.
--- @field brokerBinding number The broker binding ID for MQTT operations.
--- @field _topicValue string|nil Cached raw payload from state topic.
--- @field _valuePathResult string|nil Cached JSONPath extraction result.
--- @field _previousTopic string|nil Previous topic for subscription tracking.
--- @field _state any Cached parsed state (type varies by entity).

local JSON = require("JSON")
local log = require("lib.logging")
local values = require("lib.values")
local StateParser = require("mqtt.state_parser")

local MqttEntity = {
  TYPE = "base",
}
MqttEntity.__index = MqttEntity

--- Create a new entity instance.
--- @param item table The item configuration.
--- @param brokerBinding number The broker binding ID.
--- @return MqttEntity instance A new entity.
function MqttEntity:new(item, brokerBinding)
  local instance = setmetatable({}, self)
  instance.item = item
  instance.brokerBinding = brokerBinding
  return instance
end

--- Get the entity's item ID.
--- @return string id The item ID.
function MqttEntity:getId()
  return tostring(self.item.id)
end

--- Get the entity's name.
--- @return string name The item name.
function MqttEntity:getName()
  return self.item.name
end

--- Get the entity's state variable name.
--- @return string name The state variable's name.
function MqttEntity:getStateVarName()
  return self:getName() .. " State"
end

--- Get the cached raw topic value (payload).
--- @return string|nil payload The last payload, or nil.
function MqttEntity:getTopicValue()
  return self._topicValue
end

--- Get the cached JSONPath extraction result.
--- @return string|nil result The last extraction result, or nil.
function MqttEntity:getValuePathResult()
  return self._valuePathResult
end

--- Get the cached parsed state.
--- @return any state The parsed state.
function MqttEntity:getState()
  return self._state
end

--- Get the previous topic (for subscription change detection).
--- @return string|nil topic The previous topic, or nil.
function MqttEntity:getPreviousTopic()
  return self._previousTopic
end

--- Check if the state topic has changed.
--- @param newTopic string|nil The new topic to compare.
--- @return boolean changed True if a previous topic differs from the new one.
function MqttEntity:hasTopicChanged(newTopic)
  return self._previousTopic ~= nil and self._previousTopic ~= newTopic
end

--- Record the current topic for future change detection.
--- @param topic string|nil The current topic.
function MqttEntity:recordTopic(topic)
  self._previousTopic = topic
end

--- Extract value from payload using JSONPath if configured.
--- @param payload string Raw MQTT payload.
--- @return string|nil extractedValue The extracted value or nil on error.
--- @return string|nil resultMessage The extraction result message for display.
function MqttEntity:extractValue(payload)
  local jsonPath = self.item.valuePath
  if IsEmpty(jsonPath) then
    return payload, nil
  end

  local success, jsonTable = pcall(JSON.decode, JSON, payload)
  if not success or type(jsonTable) ~= "table" then
    local errMsg = "Error: Invalid JSON"
    log:warn("Failed to parse payload as JSON: %s", payload)
    return nil, errMsg
  end

  local value = StateParser.extractJsonPath(jsonTable, jsonPath)
  if value == nil then
    local errMsg = "Error: Path not found"
    log:warn("JSONPath '%s' not found in payload", jsonPath)
    return nil, errMsg
  end

  local strValue = tostring(value)
  return strValue, strValue
end

--- Subscribe to the entity's state topic.
--- @param deviceId string The device ID for subscription tracking.
function MqttEntity:subscribe(deviceId)
  if IsEmpty(self.item.stateTopic) then
    return
  end

  if self:hasTopicChanged(self.item.stateTopic) then
    log:debug("Unsubscribing from previous topic: %s", self._previousTopic)
    SendToProxy(self.brokerBinding, "UNSUBSCRIBE", {
      topic = self._previousTopic,
      device_id = deviceId,
    })
  end

  log:debug("Subscribing to topic: %s", self.item.stateTopic)
  SendToProxy(self.brokerBinding, "SUBSCRIBE", {
    topic = self.item.stateTopic,
    qos = self.item.qos or "0",
    device_id = deviceId,
  })

  self:recordTopic(self.item.stateTopic)
end

--- Unsubscribe from the entity's state topic.
--- @param deviceId string The device ID.
function MqttEntity:unsubscribe(deviceId)
  if IsEmpty(self.item.stateTopic) then
    return
  end

  log:debug("Unsubscribing from topic: %s", self.item.stateTopic)
  SendToProxy(self.brokerBinding, "UNSUBSCRIBE", {
    topic = self.item.stateTopic,
    device_id = deviceId,
  })
end

--- Publish a message to MQTT.
--- @param topic string The topic to publish to.
--- @param payload string The payload to publish.
--- @param qos? string QoS level (default "0").
--- @param retain? boolean Whether to retain the message.
function MqttEntity:publish(topic, payload, qos, retain)
  log:debug("Publishing to %s: %s", topic, payload)
  SendToProxy(self.brokerBinding, "PUBLISH", {
    topic = topic,
    payload = payload,
    qos = qos or self.item.qos or "0",
    retain = (retain or self.item.retain) and "true" or "false",
  })
end

--- Handle an incoming MQTT message. Override in subclass.
--- @param payload string The raw MQTT payload.
--- @param retained boolean|nil Whether this is a stored message rather than one just published.
--- @return boolean changed Whether the state changed.
function MqttEntity:onMessage(payload, retained)
  log:trace("%s:onMessage(%s, %s)", self.TYPE, payload, retained)
  self._topicValue = payload

  local extractedValue, pathResult = self:extractValue(payload)
  self._valuePathResult = pathResult

  if extractedValue == nil then
    log:debug("Entity '%s' - value extraction failed: %s", self:getName(), pathResult or "unknown")
    return false
  end

  return self:_processValue(extractedValue, payload, retained)
end

--- Process the extracted value. Override in subclass.
--- @param _value string The extracted value.
--- @param _rawPayload string The original raw payload.
--- @param _retained boolean|nil Whether this is a stored message rather than one just published.
--- @return boolean changed Whether the state changed.
function MqttEntity:_processValue(_value, _rawPayload, _retained)
  return false
end

--- The names of the variables the item owns. None by default.
--- @return string[] names The variable names.
function MqttEntity:getVariableNames()
  return {}
end

--- Create the item's variables that don't exist yet, so programming can use them before the first message.
--- Override in subclass.
function MqttEntity:seedVariables() end

--- Delete the item's variables.
function MqttEntity:deleteVariables()
  for _, name in ipairs(self:getVariableNames()) do
    values:delete(name)
  end
end

--- Create a read-only variable, empty, unless it exists.
--- @param name string The variable name.
--- @param varType string The variable type.
function MqttEntity:_seedVariable(name, varType)
  local stored = values:getValue(name)
  if stored == nil or stored.deleted then
    values:update(name, "", varType)
  end
end

--- Reset the entity's cached state.
function MqttEntity:reset()
  self._topicValue = nil
  self._valuePathResult = nil
  self._previousTopic = nil
  self._state = nil
end

--- Whether the devices bound to `bindingId` show something other than `value` in their variable `variableId`:
--- at least one does and none shows `value`. A device with nothing readable there doesn't count.
--- @param bindingId number The binding the devices are bound to.
--- @param variableId number The variable to read on each bound device.
--- @param value string The value a device would show if it agrees.
--- @return boolean differs True if the bound devices show the other value.
function MqttEntity:_boundDeviceShowsOther(bindingId, variableId, value)
  local other, same = false, false
  for deviceId in pairs(C4:GetBoundConsumerDevices(C4:GetDeviceID(), bindingId) or {}) do
    local shown = C4:GetVariable(deviceId, variableId)
    if shown ~= nil and shown ~= "" then
      if tostring(shown) == value then
        same = true
      else
        other = true
      end
    end
  end
  return other and not same
end

return MqttEntity
