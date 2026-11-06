--- MQTT Device entity.
--- Handles driver-level state: broker connection and device availability.
--- This is a singleton entity for the driver itself, not per-item.
--- @class MqttDevice
--- @field brokerBinding number The broker binding ID.
--- @field _connected boolean Broker connection status.
--- @field _available boolean|nil Device availability (nil = unknown).
--- @field _lastAvailabilityPayload string|nil Last raw availability payload.
--- @field _previousAvailabilityTopic string|nil Previous availability topic.

local JSON = require("JSON")
local log = require("lib.logging")
local values = require("lib.values")
local events = require("lib.events")
local conditionals = require("lib.conditionals")
local StateParser = require("mqtt.state_parser")

local EVENTS_NAMESPACE = "MQTTUniversal"
local AVAILABILITY_VARIABLE = "Availability Status"

local MqttDevice = {}
MqttDevice.__index = MqttDevice

--- Create the device entity.
--- @return MqttDevice instance A new device entity.
function MqttDevice:new()
  local instance = setmetatable({}, self)
  instance._connected = false
  return instance
end

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
--- @return boolean connected True if the broker is connected.
function MqttDevice:isConnected()
  return self._connected
end

--- Set the broker connection status.
--- @param connected boolean The connection status.
function MqttDevice:setConnected(connected)
  self._connected = connected
  if connected then
    log:info("MQTT broker connected")
  else
    log:warn("MQTT broker disconnected")
  end
  self:refreshStatus()
end

--- Show the broker link and the device's availability in Driver Status.
function MqttDevice:refreshStatus()
  local status = "Connected"
  if not self._connected then
    status = "Disconnected"
  elseif self._available == false then
    status = "Device unavailable"
  end
  UpdateProperty("Driver Status", status)
end

--- Parse availability from payload using "match one, default other" logic.
--- @param payload string The payload to parse.
--- @param payloadAvailable string|nil Value indicating available.
--- @param payloadNotAvailable string|nil Value indicating unavailable.
--- @return boolean|nil available True if available, false if not, nil if the payload says neither.
function MqttDevice:parseAvailability(payload, payloadAvailable, payloadNotAvailable)
  return StateParser.parse(payload, payloadAvailable or "", payloadNotAvailable or "")
end

--- Extract value from payload using JSONPath.
--- @param payload string The raw payload.
--- @param jsonPath string|nil The JSONPath expression.
--- @return string|nil extractedValue The extracted value, or nil on error.
--- @return string|nil resultMessage The extraction result message for display.
function MqttDevice:extractValue(payload, jsonPath)
  if IsEmpty(jsonPath) then
    return payload, nil
  end

  local success, jsonTable = pcall(JSON.decode, JSON, payload)
  if not success or type(jsonTable) ~= "table" then
    return nil, "Error: Invalid JSON"
  end

  local value = StateParser.extractJsonPath(jsonTable, jsonPath)
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
  UpdateProperty("Availability Topic Value", rawPayload or "")

  local effectivePayload, pathResult = self:extractValue(rawPayload, config.valuePath)

  if not IsEmpty(config.valuePath) then
    UpdateProperty("Availability Value Path Result", pathResult or "")
  end

  if effectivePayload == nil then
    log:debug("Availability extraction failed: %s", pathResult or "unknown")
    return false
  end

  local available = self:parseAvailability(effectivePayload, config.payloadAvailable, config.payloadNotAvailable)

  if available == nil then
    log:debug("Could not determine availability from payload: %s", effectivePayload)
    return false
  end

  self._available = available
  self:refreshStatus()

  local stored = values:getValue(AVAILABILITY_VARIABLE)
  if not values:update(AVAILABILITY_VARIABLE, available and "Available" or "Unavailable", "STRING") then
    return false
  end

  -- The variable outlasts a restart, so a change while the controller was down fires too. The first
  -- availability heard, with nothing before it, sets it silently.
  if not IsEmpty(stored and stored.value) then
    events:fire(EVENTS_NAMESPACE, available and "device_available" or "device_unavailable")
  end

  log:info("Device availability: %s", available and "available" or "unavailable")
  return true
end

--- Forget the device's availability, as when the Availability Topic changes: its readings go blank and Driver
--- Status shows the broker link alone.
function MqttDevice:clearAvailability()
  self._available = nil
  self._lastAvailabilityPayload = nil
  UpdateProperty("Availability Topic Value", "")
  UpdateProperty("Availability Value Path Result", "")
  if values:getValue(AVAILABILITY_VARIABLE) ~= nil then
    values:update(AVAILABILITY_VARIABLE, "", "STRING")
  end
  self:refreshStatus()
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

  if self._previousAvailabilityTopic and self._previousAvailabilityTopic ~= topic then
    log:debug("Unsubscribing from previous availability topic: %s", self._previousAvailabilityTopic)
    SendToProxy(self.brokerBinding, "UNSUBSCRIBE", {
      topic = self._previousAvailabilityTopic,
      device_id = deviceId,
    })
  end

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

--- Declare the availability events and conditional, and create the Availability Status variable if missing.
--- Once declared they stay with no topic set too: deleting an event deletes the programming on it.
--- @param hasAvailabilityTopic boolean Whether availability topic is configured.
function MqttDevice:registerAvailabilityEvents(hasAvailabilityTopic)
  local declared = Select(conditionals:getConditionals(), EVENTS_NAMESPACE, "device_available") ~= nil
  if not hasAvailabilityTopic and not declared then
    return
  end

  if values:getValue(AVAILABILITY_VARIABLE) == nil then
    values:update(AVAILABILITY_VARIABLE, "", "STRING")
  end

  events:getOrAddEvent(EVENTS_NAMESPACE, "device_available", "Device Available", "When NAME becomes available")
  events:getOrAddEvent(EVENTS_NAMESPACE, "device_unavailable", "Device Unavailable", "When NAME becomes unavailable")

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

--- Reset all device state.
function MqttDevice:reset()
  self._connected = false
  self._available = nil
  self._lastAvailabilityPayload = nil
  self._previousAvailabilityTopic = nil
end

return MqttDevice:new()
