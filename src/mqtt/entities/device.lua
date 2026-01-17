--- MQTT Device entity.
--- Handles driver-level state: broker connection and device availability.
--- This is a singleton entity for the driver itself, not per-item.
--- @class MqttDevice
--- @field brokerBinding number The broker binding ID.
--- @field _connected boolean Broker connection status.
--- @field _available boolean|nil Device availability (nil = unknown).
--- @field _lastAvailabilityPayload string|nil Last raw availability payload.
--- @field _previousAvailabilityTopic string|nil Previous availability topic.

local log = require("lib.logging")
local values = require("lib.values")
local events = require("lib.events")
local conditionals = require("lib.conditionals")
local stateParser = require("mqtt.state_parser")

local EVENTS_NAMESPACE = "MQTTUniversal"

local MqttDevice = {
  TYPE = "DEVICE",
  brokerBinding = nil,
  _connected = false,
  _available = nil,
  _lastAvailabilityPayload = nil,
  _previousAvailabilityTopic = nil,
}

--- Initialize the device with the broker binding.
--- @param brokerBinding number The broker binding ID.
function MqttDevice:init(brokerBinding)
  self.brokerBinding = brokerBinding
  self._connected = false
  self._available = nil
  self._lastAvailabilityPayload = nil
  self._previousAvailabilityTopic = nil
end

--- Check if the broker is connected.
--- @return boolean
function MqttDevice:isConnected()
  return self._connected
end

--- Set the broker connection status.
--- @param connected boolean The connection status.
function MqttDevice:setConnected(connected)
  self._connected = connected
  if connected then
    log:info("MQTT broker connected")
    UpdateProperty("Driver Status", "Connected")
  else
    log:warn("MQTT broker disconnected")
    UpdateProperty("Driver Status", "Disconnected")
  end
end

--- Check if the device is available.
--- @return boolean|nil nil = unknown, true = available, false = unavailable.
function MqttDevice:isAvailable()
  return self._available
end

--- Get the last availability payload.
--- @return string|nil
function MqttDevice:getLastAvailabilityPayload()
  return self._lastAvailabilityPayload
end

--- Parse availability from payload using "match one, default other" logic.
--- @param payload string The payload to parse.
--- @param payloadAvailable string|nil Value indicating available.
--- @param payloadNotAvailable string|nil Value indicating unavailable.
--- @return boolean|nil
function MqttDevice:parseAvailability(payload, payloadAvailable, payloadNotAvailable)
  return stateParser.parse(payload, payloadAvailable or "", payloadNotAvailable or "")
end

--- Extract value from payload using JSONPath.
--- @param payload string The raw payload.
--- @param jsonPath string|nil The JSONPath expression.
--- @return string|nil extractedValue
--- @return string|nil resultMessage
function MqttDevice:extractValue(payload, jsonPath)
  if not jsonPath or jsonPath == "" then
    return payload, nil
  end

  local success, jsonTable = pcall(JSON.decode, JSON, payload)
  if not success or type(jsonTable) ~= "table" then
    return nil, "Error: Invalid JSON"
  end

  local value = stateParser.extractJsonPath(jsonTable, jsonPath)
  if value == nil then
    return nil, "Error: Path not found"
  end

  return tostring(value), tostring(value)
end

--- Update device availability from MQTT payload.
--- @param rawPayload string The raw availability payload.
--- @param config table Configuration with valuePath, payloadAvailable, payloadNotAvailable.
--- @return boolean changed Whether availability changed.
function MqttDevice:updateAvailability(rawPayload, config)
  log:trace("MqttDevice:updateAvailability(%s)", rawPayload)
  self._lastAvailabilityPayload = rawPayload

  -- Update topic value property
  UpdateProperty("Availability Topic Value", rawPayload or "")

  -- Extract value using JSONPath if configured
  local effectivePayload, pathResult = self:extractValue(rawPayload, config.valuePath)

  if not IsEmpty(config.valuePath) then
    UpdateProperty("Availability Value Path Result", pathResult or "")
  end

  if effectivePayload == nil then
    log:debug("Availability extraction failed: %s", pathResult or "unknown")
    return false
  end

  local wasKnown = self._available ~= nil
  local available = self:parseAvailability(effectivePayload, config.payloadAvailable, config.payloadNotAvailable)

  if available == nil then
    log:debug("Could not determine availability from payload: %s", effectivePayload)
    return false
  end

  if self._available == available then
    return false
  end

  self._available = available

  -- Update availability variable
  values:update("Availability Status", available and "Available" or "Unavailable", "STRING")

  if available then
    UpdateProperty("Driver Status", "Connected")
    if wasKnown then
      events:fire(EVENTS_NAMESPACE, "device_available")
    end
  else
    if wasKnown then
      UpdateProperty("Driver Status", "Device unavailable")
      events:fire(EVENTS_NAMESPACE, "device_unavailable")
    end
  end

  log:info("Device availability: %s", available and "available" or "unavailable")
  return true
end

--- Re-evaluate availability with current payload and new config.
--- @param config table The new configuration.
function MqttDevice:reevaluateAvailability(config)
  if self._lastAvailabilityPayload then
    self:updateAvailability(self._lastAvailabilityPayload, config)
  end
end

--- Subscribe to the availability topic.
--- @param topic string|nil The availability topic.
--- @param deviceId string The device ID for subscription.
function MqttDevice:subscribeToAvailability(topic, deviceId)
  if not self._connected then
    return
  end

  -- Unsubscribe from previous topic if changed
  if self._previousAvailabilityTopic and self._previousAvailabilityTopic ~= topic then
    log:debug("Unsubscribing from previous availability topic: %s", self._previousAvailabilityTopic)
    SendToProxy(self.brokerBinding, "UNSUBSCRIBE", {
      topic = self._previousAvailabilityTopic,
      device_id = deviceId,
    })
  end

  -- Subscribe to new topic
  if not IsEmpty(topic) then
    log:debug("Subscribing to availability topic: %s", topic)
    SendToProxy(self.brokerBinding, "SUBSCRIBE", {
      topic = topic,
      qos = "0",
      device_id = deviceId,
    })
  end

  self._previousAvailabilityTopic = topic
end

--- Register availability events and conditional.
--- @param hasAvailabilityTopic boolean Whether availability topic is configured.
function MqttDevice:registerAvailabilityEvents(hasAvailabilityTopic)
  if not hasAvailabilityTopic then
    return
  end

  events:getOrAddEvent(EVENTS_NAMESPACE, "device_available", "Device Available", "When device becomes available")
  events:getOrAddEvent(EVENTS_NAMESPACE, "device_unavailable", "Device Unavailable", "When device becomes unavailable")

  local device = self
  conditionals:upsertConditional(EVENTS_NAMESPACE, "device_available", {
    type = "BOOL",
    condition_statement = "Device availability status",
    description = "NAME device is STRING",
    true_text = "Available",
    false_text = "Unavailable",
  }, function(strConditionName, tParams)
    log:trace("TC availability condition=%s, tParams=%s", strConditionName, tParams)
    local test = Select(tParams, "VALUE") == "Available"
    if Select(tParams, "LOGIC") == "NOT_EQUAL" then
      return test ~= device._available
    else
      return test == device._available
    end
  end)

  log:debug("Registered availability events and conditional")
end

--- Unregister availability events and conditional.
function MqttDevice:unregisterAvailabilityEvents()
  events:deleteEvent(EVENTS_NAMESPACE, "device_available")
  events:deleteEvent(EVENTS_NAMESPACE, "device_unavailable")
  conditionals:deleteConditional(EVENTS_NAMESPACE, "device_available")
  log:debug("Unregistered availability events and conditional")
end

--- Reset all device state.
function MqttDevice:reset()
  self._connected = false
  self._available = nil
  self._lastAvailabilityPayload = nil
  self._previousAvailabilityTopic = nil
end

return MqttDevice
