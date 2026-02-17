--- MQTT Bridge Driver
--- A Control4 driver for bridging C4 devices to MQTT.
---
--- This driver connects to an MQTT broker (via the MQTT Broker driver) and
--- publishes device state changes to MQTT topics. It also subscribes to command
--- topics to allow external systems to monitor and control C4 devices.
---
--- Topic structure:
---   {prefix}/{device_id}/state   - Published state (retained)
---   {prefix}/{device_id}/command - Subscribed for commands
---   {prefix}/{device_id}/config  - Published device metadata (retained)

--#ifdef DRIVERCENTRAL
DC_PID = 858
DC_X = nil
DC_FILENAME = "mqtt_bridge.c4z"
--#endif

require("lib.utils")
require("drivers-common-public.global.handlers")
require("drivers-common-public.global.lib")
require("drivers-common-public.global.timer")
require("drivers-common-public.global.url")

local log = require("lib.logging")
local persist = require("lib.persist")

-- Binding IDs
local MQTT_BINDING = 5001

-- Variable IDs for lights
local LIGHT_LEVEL_VAR = 1001

-- Persistence keys
local LIGHTS_PERSIST_KEY = "Lights"

-- Track broker connection state
local brokerConnected = false

-- Track selected lights: { [deviceId] = { name, room, type, level } }
local lights = {}

-----------------------------------------------------------------------
-- Helper functions
-----------------------------------------------------------------------

--- Get the topic prefix from properties
--- @return string
local function getTopicPrefix()
  local prefix = Properties["Topic Prefix"] or "c4"
  -- Remove trailing slash if present
  return (prefix:gsub("/$", ""))
end

--- Get the QoS setting from properties
--- @return string
local function getQoS()
  return Properties["QoS"] or "0"
end

--- Build topic for a light device
--- @param deviceId number Device ID
--- @param suffix string Topic suffix (state, command, config)
--- @return string
local function buildLightTopic(deviceId, suffix)
  return string.format("%s/light/%d/%s", getTopicPrefix(), deviceId, suffix)
end

--- Get device display name
--- @param deviceId number Device ID
--- @param deviceType string Device type (e.g. "Light")
--- @return string
local function getDeviceName(deviceId, deviceType)
  local name = C4:GetDeviceDisplayName(deviceId)
  return name or (deviceType .. " " .. tostring(deviceId))
end

--- Get room name for a device
--- @param deviceId number Device ID
--- @return string
local function getDeviceRoom(deviceId)
  local devices = C4:GetDevices({ DeviceIds = tostring(deviceId) })
  local roomName = Select(devices, deviceId, "roomName")
  return not IsEmpty(roomName) and roomName or "Unknown"
end

--- Get light setup value from the device
--- @param deviceId number Device ID
--- @param key string Setup key to retrieve
--- @return any
local function getLightSetup(deviceId, key)
  local response = SendUIRequest(deviceId, "GET_SETUP", {})
  if IsEmpty(response) then
    return nil
  end
  return Select(ParseXml(response), "setup", key)
end

--- Check if device is a dimmer (supports level control)
--- @param deviceId number Device ID
--- @return boolean
local function lightIsDimmer(deviceId)
  return toboolean(getLightSetup(deviceId, "dimmer"))
    or toboolean(getLightSetup(deviceId, "set_level"))
    or toboolean(getLightSetup(deviceId, "ramp_level"))
end

--- Get device type (dimmer or switch)
--- @param deviceId number Device ID
--- @return string "dimmer" or "switch"
local function getDeviceType(deviceId)
  return lightIsDimmer(deviceId) and "dimmer" or "switch"
end

--- Encode a table as JSON
--- @param tbl table Table to encode
--- @return string
local function jsonEncode(tbl)
  return JSON:encode(tbl) or "{}"
end

--- Decode JSON string to table
--- @param str string JSON string
--- @return table|nil
local function jsonDecode(str)
  if not str or str == "" then
    return nil
  end

  local success, result = xpcall(JSON.decode, debug.traceback, JSON, str)
  if success then
    return result
  end
  return nil
end

-----------------------------------------------------------------------
-- MQTT Publishing
-----------------------------------------------------------------------

--- Publish a message to MQTT
--- @param topic string Topic to publish to
--- @param payload string Payload to publish
--- @param retain boolean Whether to retain the message
local function publish(topic, payload, retain)
  if not brokerConnected then
    log:debug("Not publishing (broker disconnected): %s", topic)
    return
  end

  log:debug("Publishing to %s: %s (retain=%s)", topic, payload, tostring(retain))
  SendToProxy(MQTT_BINDING, "PUBLISH", {
    topic = topic,
    payload = payload,
    qos = getQoS(),
    retain = retain and "true" or "false",
  })
end

--- Publish light state to MQTT
--- @param deviceId number Device ID
--- @param level number Light level (0-100)
local function publishLightState(deviceId, level)
  local light = lights[deviceId]
  if not light then
    return
  end

  local state = {
    on = level > 0,
    level = level,
  }

  local topic = buildLightTopic(deviceId, "state")
  local payload = jsonEncode(state)
  publish(topic, payload, true)

  log:info("Published state for '%s': level=%d", light.name, level)
end

--- Publish light config to MQTT
--- @param deviceId number Device ID
local function publishLightConfig(deviceId)
  local light = lights[deviceId]
  if not light then
    return
  end

  local config = {
    name = light.name,
    room = light.room,
    type = light.type,
  }

  local topic = buildLightTopic(deviceId, "config")
  local payload = jsonEncode(config)
  publish(topic, payload, true)

  log:info("Published config for '%s' (id=%d)", light.name, deviceId)
end

--- Clear retained messages for a light (when unselected)
--- @param deviceId number Device ID
local function clearLightTopics(deviceId)
  -- Publish empty retained message to clear
  publish(buildLightTopic(deviceId, "state"), "", true)
  publish(buildLightTopic(deviceId, "config"), "", true)
  log:debug("Cleared topics for device %d", deviceId)
end

-----------------------------------------------------------------------
-- MQTT Subscription
-----------------------------------------------------------------------

--- Subscribe to command topic for a light
--- @param deviceId number Device ID
local function subscribeLight(deviceId)
  if not brokerConnected then
    return
  end

  local topic = buildLightTopic(deviceId, "command")
  local driverId = tostring(C4:GetDeviceID())

  log:debug("Subscribing to command topic: %s", topic)
  SendToProxy(MQTT_BINDING, "SUBSCRIBE", {
    topic = topic,
    qos = getQoS(),
    device_id = driverId,
  })
end

--- Unsubscribe from command topic for a light
--- @param deviceId number Device ID
local function unsubscribeLight(deviceId)
  local topic = buildLightTopic(deviceId, "command")
  local driverId = tostring(C4:GetDeviceID())

  log:debug("Unsubscribing from command topic: %s", topic)
  SendToProxy(MQTT_BINDING, "UNSUBSCRIBE", {
    topic = topic,
    device_id = driverId,
  })
end

--- Subscribe to all light command topics
local function subscribeAllLights()
  for deviceId, _ in pairs(lights) do
    subscribeLight(deviceId)
  end
end

-----------------------------------------------------------------------
-- Variable Listener Management
-----------------------------------------------------------------------

--- Handle light level change from C4
--- @param deviceId number Device ID
--- @param variableId number Variable ID
--- @param strValue string Variable value as string
local function onLightLevelChanged(deviceId, variableId, strValue)
  log:trace("onLightLevelChanged(%d, %d, %s)", deviceId, variableId, strValue)

  local level = tonumber(strValue) or 0
  local light = lights[deviceId]
  if not light then
    log:warn("Received level change for unknown light: %d", deviceId)
    return
  end

  -- Update cached level
  light.level = level

  -- Publish to MQTT
  publishLightState(deviceId, level)
end

--- Register variable listener for a light
--- @param deviceId number Device ID
local function registerLightListener(deviceId)
  log:debug("Registering variable listener for device %d", deviceId)
  RegisterVariableListener(deviceId, LIGHT_LEVEL_VAR, onLightLevelChanged)
end

--- Unregister variable listener for a light
--- @param deviceId number Device ID
local function unregisterLightListener(deviceId)
  log:debug("Unregistering variable listener for device %d", deviceId)
  UnregisterVariableListener(deviceId, LIGHT_LEVEL_VAR)
end

-----------------------------------------------------------------------
-- Light Management
-----------------------------------------------------------------------

--- Get current light level from C4
--- @param deviceId number Device ID
--- @return number level (0-100)
local function getCurrentLevel(deviceId)
  return tointeger(C4:GetVariable(deviceId, LIGHT_LEVEL_VAR)) or 0
end

--- Add a light to tracking
--- @param deviceId number Device ID
local function addLight(deviceId)
  if lights[deviceId] then
    return -- Already tracking
  end

  local name = getDeviceName(deviceId, "Light")
  local room = getDeviceRoom(deviceId)
  local deviceType = getDeviceType(deviceId)
  local level = getCurrentLevel(deviceId)

  lights[deviceId] = {
    name = name,
    room = room,
    type = deviceType,
    level = level,
  }

  log:info("Added light '%s' (id=%d, room=%s, type=%s)", name, deviceId, room, deviceType)

  -- Register for state changes
  registerLightListener(deviceId)

  -- Subscribe to commands
  if brokerConnected then
    subscribeLight(deviceId)
    -- Publish initial config and state
    publishLightConfig(deviceId)
    publishLightState(deviceId, level)
  end
end

--- Remove a light from tracking
--- @param deviceId number Device ID
local function removeLight(deviceId)
  local light = lights[deviceId]
  if not light then
    return
  end

  log:info("Removing light '%s' (id=%d)", light.name, deviceId)

  -- Unregister listener
  unregisterLightListener(deviceId)

  -- Unsubscribe and clear topics
  if brokerConnected then
    unsubscribeLight(deviceId)
    clearLightTopics(deviceId)
  end

  lights[deviceId] = nil
end

--- Parse device IDs from DEVICE_SELECTOR property value
--- @param propertyValue string Comma-separated device IDs
--- @return table<number, boolean> Set of device IDs
local function parseDeviceIds(propertyValue)
  local ids = {}
  if IsEmpty(propertyValue) then
    return ids
  end

  for id in string.gmatch(propertyValue, "(%d+)") do
    local deviceId = tonumber(id)
    if deviceId then
      ids[deviceId] = true
    end
  end

  return ids
end

--- Update selected lights based on property value
--- @param propertyValue string Comma-separated device IDs
local function updateSelectedLights(propertyValue)
  log:trace("updateSelectedLights(%s)", propertyValue)

  local newIds = parseDeviceIds(propertyValue)

  -- Find lights to remove (in current but not in new)
  local toRemove = {}
  for deviceId, _ in pairs(lights) do
    if not newIds[deviceId] then
      table.insert(toRemove, deviceId)
    end
  end

  -- Find lights to add (in new but not in current)
  local toAdd = {}
  for deviceId, _ in pairs(newIds) do
    if not lights[deviceId] then
      table.insert(toAdd, deviceId)
    end
  end

  -- Remove deselected lights
  for _, deviceId in ipairs(toRemove) do
    removeLight(deviceId)
  end

  -- Add newly selected lights
  for _, deviceId in ipairs(toAdd) do
    addLight(deviceId)
  end

  -- Persist selection
  persist:set(LIGHTS_PERSIST_KEY, propertyValue)
end

--- Republish all light states and configs (on broker connect)
local function republishAllLights()
  for deviceId, light in pairs(lights) do
    publishLightConfig(deviceId)
    publishLightState(deviceId, light.level)
  end
end

-----------------------------------------------------------------------
-- Command Handling
-----------------------------------------------------------------------

--- Handle incoming MQTT command for a light
--- @param deviceId number Device ID
--- @param payload string JSON command payload
local function handleLightCommand(deviceId, payload)
  local light = lights[deviceId]
  if not light then
    log:warn("Received command for unknown light: %d", deviceId)
    return
  end

  local cmd = jsonDecode(payload)
  if not cmd then
    log:warn("Invalid command payload for light %d: %s", deviceId, payload)
    return
  end

  log:debug("Received command for '%s': %s", light.name, payload)

  -- Determine target level
  local targetLevel = nil

  if cmd.level ~= nil then
    -- Explicit level specified
    targetLevel = tonumber(cmd.level)
    if targetLevel then
      targetLevel = math.max(0, math.min(100, targetLevel))
    end
  elseif cmd.on ~= nil then
    -- Just on/off specified
    if cmd.on == true or cmd.on == "true" or cmd.on == 1 then
      -- Turn on - use 100 or last level
      targetLevel = 100
    else
      -- Turn off
      targetLevel = 0
    end
  end

  if targetLevel == nil then
    log:warn("Could not determine target level from command: %s", payload)
    return
  end

  log:info("Setting '%s' to level %d", light.name, targetLevel)

  -- Send command to C4 device
  C4:SendToDevice(deviceId, "SET_BRIGHTNESS_TARGET", { LEVEL = targetLevel })
end

--- Parse device ID from command topic
--- @param topic string Full topic
--- @return number|nil Device ID or nil
local function parseDeviceIdFromTopic(topic)
  local prefix = getTopicPrefix()
  -- Escape special pattern characters in prefix
  local escapedPrefix = prefix:gsub("([%.%+%-%*%?%[%]%^%$%(%)%%])", "%%%1")
  local pattern = "^" .. escapedPrefix .. "/light/(%d+)/command$"
  local idStr = topic:match(pattern)
  if idStr then
    return tonumber(idStr)
  end
  return nil
end

-----------------------------------------------------------------------
-- Driver lifecycle
-----------------------------------------------------------------------

function OnDriverInit()
  --#ifdef DRIVERCENTRAL
  require("cloud-client-byte")
  C4:AllowExecute(false)
  --#else
  C4:AllowExecute(true)
  --#endif
  gInitialized = false
  log:setLogName(C4:GetDeviceData(C4:GetDeviceID(), "name"))
  log:setLogLevel(Properties["Log Level"])
  log:setLogMode(Properties["Log Mode"])
  log:trace("OnDriverInit()")
end

function OnDriverLateInit()
  log:trace("OnDriverLateInit()")
  if not CheckMinimumVersion("Driver Status") then
    return
  end
  UpdateProperty("Driver Status", "Initializing")

  -- Restore persisted light selection
  local savedSelection = persist:get(LIGHTS_PERSIST_KEY, "")
  if not IsEmpty(savedSelection) then
    log:debug("Restoring saved light selection: %s", savedSelection)
    updateSelectedLights(savedSelection)
  end

  -- Fire OnPropertyChanged to set the initial Headers and other Property
  -- global sets, they'll change if Property is changed.
  for p, _ in pairs(Properties) do
    local status, err = pcall(OnPropertyChanged, p)
    if not status and err then
      log:error("Error in OnPropertyChanged for property '%s': %s", p, err or "unknown error")
    end
  end
  gInitialized = true
  UpdateProperty("Driver Status", "Disconnected")

  -- Request current broker status
  SendToProxy(MQTT_BINDING, "GET_STATUS", {}, "NOTIFY")
end

-----------------------------------------------------------------------
-- Property change handlers
-----------------------------------------------------------------------

function OPC.Driver_Version(propertyValue)
  log:trace("OPC.Driver_Version('%s')", propertyValue)
  C4:UpdateProperty("Driver Version", C4:GetDriverConfigInfo("version"))
end

function OPC.Log_Mode(propertyValue)
  log:trace("OPC.Log_Mode('%s')", propertyValue)
  log:setLogMode(propertyValue)
  CancelTimer("LogMode")
  if not log:isEnabled() then
    return
  end
  log:warn("Log mode '%s' will expire in 3 hours", propertyValue)
  SetTimer("LogMode", 3 * ONE_HOUR, function()
    log:warn("Setting log mode to 'Off' (timer expired)")
    UpdateProperty("Log Mode", "Off", true)
  end)
end

function OPC.Log_Level(propertyValue)
  log:trace("OPC.Log_Level('%s')", propertyValue)
  log:setLogLevel(propertyValue)
  if log:getLogLevel() >= 6 and log:isPrintEnabled() then
    DEBUGPRINT = true
    DEBUG_TIMER = true
    DEBUG_RFN = true
    DEBUG_URL = true
  else
    DEBUGPRINT = false
    DEBUG_TIMER = false
    DEBUG_RFN = false
    DEBUG_URL = false
  end
end

function OPC.Select_Lights(propertyValue)
  log:trace("OPC.Select_Lights('%s')", propertyValue)
  if not gInitialized then
    return
  end
  updateSelectedLights(propertyValue)

  -- Republish all lights to ensure MQTT state is current
  -- (handles case where user reselects same lights to force refresh)
  if brokerConnected then
    republishAllLights()
  end
end

function OPC.Topic_Prefix(propertyValue)
  log:trace("OPC.Topic_Prefix('%s')", propertyValue)
  if not gInitialized then
    return
  end

  -- Re-subscribe all lights with new prefix
  -- First unsubscribe old topics
  for deviceId, _ in pairs(lights) do
    unsubscribeLight(deviceId)
  end

  -- Then subscribe with new prefix and republish
  if brokerConnected then
    subscribeAllLights()
    republishAllLights()
  end
end

function OPC.QoS(propertyValue)
  log:trace("OPC.QoS('%s')", propertyValue)
  -- QoS change takes effect on next publish/subscribe
end

-----------------------------------------------------------------------
-- Receive From Proxy (RFP) handlers
-----------------------------------------------------------------------

function RFP.BROKER_CONNECTED(idBinding, strCommand, tParams, args)
  log:trace("RFP.BROKER_CONNECTED(%s, %s, %s, %s)", idBinding, strCommand, tParams, args)
  if idBinding ~= MQTT_BINDING then
    return
  end

  brokerConnected = true
  UpdateProperty("Driver Status", "Connected")
  log:info("MQTT broker connected")

  -- Subscribe to command topics and publish current state
  subscribeAllLights()
  republishAllLights()
end

function RFP.BROKER_DISCONNECTED(idBinding, strCommand, tParams, args)
  log:trace("RFP.BROKER_DISCONNECTED(%s, %s, %s, %s)", idBinding, strCommand, tParams, args)
  if idBinding ~= MQTT_BINDING then
    return
  end

  brokerConnected = false
  UpdateProperty("Driver Status", "Disconnected")
  log:warn("MQTT broker disconnected")
end

-----------------------------------------------------------------------
-- On Binding Changed (OBC) handler
-----------------------------------------------------------------------

OBC[MQTT_BINDING] = function(idBinding, strClass, bIsBound, otherDeviceId, otherBindingId)
  log:trace("OBC[MQTT_BINDING](%s, %s, %s, %s, %s)", idBinding, strClass, bIsBound, otherDeviceId, otherBindingId)
  brokerConnected = false
  UpdateProperty("Driver Status", "Disconnected")
  if bIsBound then
    SendToProxy(MQTT_BINDING, "GET_STATUS", {}, "NOTIFY")
  end
end

-----------------------------------------------------------------------
-- Execute Command (EC) handlers
-----------------------------------------------------------------------

function EC.MQTT_MESSAGE(tParams)
  log:trace("EC.MQTT_MESSAGE(%s)", tParams)

  local topic = Select(tParams, "topic")
  local payload = Select(tParams, "payload")

  log:debug("Received MQTT message: topic=%s payload=%s", topic, payload)

  -- Check if this is a command for one of our lights
  local deviceId = parseDeviceIdFromTopic(topic)
  if deviceId then
    handleLightCommand(deviceId, payload)
  end
end
