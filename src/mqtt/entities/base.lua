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

local log = require("lib.logging")
local stateParser = require("mqtt.state_parser")

local MqttEntity = {
  TYPE = "base",
}

--- Create a new entity instance.
--- @param item table The item configuration.
--- @param brokerBinding number The broker binding ID.
--- @return MqttEntity
function MqttEntity:new(item, brokerBinding)
  local instance = {
    item = item,
    brokerBinding = brokerBinding,
    _topicValue = nil,
    _valuePathResult = nil,
    _previousTopic = nil,
    _state = nil,
  }
  setmetatable(instance, self)
  self.__index = self
  return instance
end

--- Get the entity's item ID.
--- @return string
function MqttEntity:getId()
  return tostring(self.item.id)
end

--- Get the entity's name.
--- @return string
function MqttEntity:getName()
  return self.item.name
end

--- Get the entity's state variable name.
--- @return string
function MqttEntity:getStateVarName()
  return self:getName() .. " State"
end

--- Get the cached raw topic value (payload).
--- @return string|nil
function MqttEntity:getTopicValue()
  return self._topicValue
end

--- Get the cached JSONPath extraction result.
--- @return string|nil
function MqttEntity:getValuePathResult()
  return self._valuePathResult
end

--- Get the cached parsed state.
--- @return any
function MqttEntity:getState()
  return self._state
end

--- Get the previous topic (for subscription change detection).
--- @return string|nil
function MqttEntity:getPreviousTopic()
  return self._previousTopic
end

--- Check if the state topic has changed.
--- @param newTopic string|nil The new topic to compare.
--- @return boolean
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

  -- No path configured, use raw payload
  if not jsonPath or jsonPath == "" then
    return payload, nil
  end

  -- Try to parse as JSON
  local success, jsonTable = pcall(JSON.decode, JSON, payload)
  if not success or type(jsonTable) ~= "table" then
    local errMsg = "Error: Invalid JSON"
    log:warn("Failed to parse payload as JSON: %s", payload)
    return nil, errMsg
  end

  local value = stateParser.extractJsonPath(jsonTable, jsonPath)
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

  -- Unsubscribe from previous topic if changed
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
--- @param qos string|nil QoS level (default "0").
--- @param retain boolean|nil Whether to retain the message.
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
--- @return boolean changed Whether the state changed.
function MqttEntity:onMessage(payload)
  log:trace("%s:onMessage(%s)", self.TYPE, payload)
  self._topicValue = payload

  -- Extract value using JSONPath if configured
  local extractedValue, pathResult = self:extractValue(payload)
  self._valuePathResult = pathResult

  if extractedValue == nil then
    log:debug("Entity '%s' - value extraction failed: %s", self:getName(), pathResult or "unknown")
    return false
  end

  -- Subclasses override to handle the extracted value
  return self:_processValue(extractedValue, payload)
end

--- Process the extracted value. Override in subclass.
--- @param value string The extracted value.
--- @param rawPayload string The original raw payload.
--- @return boolean changed Whether the state changed.
function MqttEntity:_processValue(value, rawPayload)
  -- Base implementation does nothing
  return false
end

--- Reset the entity's cached state.
function MqttEntity:reset()
  self._topicValue = nil
  self._valuePathResult = nil
  self._previousTopic = nil
  self._state = nil
end

return MqttEntity
