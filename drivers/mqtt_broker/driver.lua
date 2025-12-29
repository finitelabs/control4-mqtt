--#ifdef DRIVERCENTRAL
DC_PID = 857
DC_X = nil
DC_FILENAME = "mqtt_broker.c4z"
--#else
DRIVER_GITHUB_REPO = "finitelabs/control4-mqtt"
DRIVER_FILENAMES = {
  "mqtt_broker.c4z",
  "mqtt_button.c4z",
  "mqtt_contact.c4z",
  "mqtt_switch.c4z",
}
--#endif

require("lib.utils")
require("vendor.drivers-common-public.global.handlers")
require("vendor.drivers-common-public.global.lib")
require("vendor.drivers-common-public.global.timer")
require("vendor.drivers-common-public.global.url")

local log = require("lib.logging")
--#ifndef DRIVERCENTRAL
local githubUpdater = require("lib.github-updater")
--#endif

-- MQTT client instance
local MQTT = nil
local MQTT_CONNECTED = false

-- Track subscriptions: topic -> {deviceId -> true}
local subscriptions = {}

-- Cache last message per topic for new subscribers
local lastMessages = {}

-- Binding ID for the MQTT_BROKER connection
local MQTT_BROKER_BINDING = 5001

function OnDriverInit()
  --#ifdef DRIVERCENTRAL
  require("vendor.cloud-client-byte")
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

  C4:FileSetDir("c29tZXNwZWNpYWxrZXk=++11")

  -- Fire OnPropertyChanged to set the initial Headers and other Property
  -- global sets, they'll change if Property is changed.
  for p, _ in pairs(Properties) do
    local status, err = pcall(OnPropertyChanged, p)
    if not status and err ~= nil then
      log:error(err)
    end
  end
  gInitialized = true
  Connect()
end

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

function OPC.Broker_Address(propertyValue)
  log:trace("OPC.Broker_Address('%s')", propertyValue)
  Connect()
end

function OPC.Port(propertyValue)
  log:trace("OPC.Port('%s')", propertyValue)
  Connect()
end

function OPC.Username(propertyValue)
  log:trace("OPC.Username('%s')", propertyValue)
  Connect()
end

function OPC.Password(propertyValue)
  log:trace("OPC.Password('%s')", not IsEmpty(propertyValue) and "****" or "")
  Connect()
end

function OPC.Keep_Alive(propertyValue)
  log:trace("OPC.Keep_Alive('%s')", propertyValue)
  Connect()
end

local function updateStatus(status)
  log:trace("updateStatus(%s)", status)
  UpdateProperty("Driver Status", not IsEmpty(status) and status or "Unknown")
end

--- Notify all connected child drivers of an event
--- @param command string The command to send
--- @param params table The parameters to send
local function notifyChildDrivers(command, params)
  log:trace("notifyChildDrivers(%s, %s)", command, params)
  -- SendToProxy broadcasts to all devices connected to this binding
  SendToProxy(MQTT_BROKER_BINDING, command, params or {}, "NOTIFY")
end

--- Route incoming MQTT messages to subscribed child drivers
--- @param topic string The topic the message was received on
--- @param payload string The message payload
--- @param qos number The QoS level
--- @param retain boolean Whether the message was retained
local function routeMessageToSubscribers(topic, payload, qos, retain)
  log:trace("routeMessageToSubscribers('%s', '%s', %s, %s)", topic, payload, qos, retain)

  -- Check for exact topic match
  local devices = subscriptions[topic]
  if not IsEmpty(devices) then
    for deviceId, _ in pairs(devices) do
      log:debug("Routing message to device %s", deviceId)
      -- Use C4:SendToDevice for targeted messages to specific subscribers
      SendToDevice(deviceId, "MQTT_MESSAGE", {
        topic = topic,
        payload = payload,
        qos = tostring(qos),
        retain = retain and "true" or "false",
      })
    end
  end
end

function Connect()
  log:trace("Connect()")
  if not gInitialized then
    updateStatus("Initializing...")
    return
  end

  -- Cancel any pending reconnect
  CancelTimer("reconnect")

  -- Notify children we're disconnecting before reconnecting
  notifyChildDrivers("BROKER_DISCONNECTED", {})

  -- Disconnect existing connection
  if MQTT then
    log:debug("Disconnecting existing MQTT connection")
    MQTT:Disconnect()
    MQTT = nil
  end
  MQTT_CONNECTED = false

  local brokerAddress = Properties["Broker Address"]
  local port = tonumber(Properties["Port"]) or 1883

  if IsEmpty(brokerAddress) then
    updateStatus("Not configured")
    return
  end

  --#ifdef DRIVERCENTRAL
  if DC_X == 0 then
    updateStatus("No active license")
    return
  end
  --#endif

  local clientId = "control4-mqtt-device-" .. C4:GetDeviceID()
  log:info("Creating MQTT client with clientId: %s", clientId)
  MQTT = C4:MQTT(clientId)

  -- Set credentials if provided
  local username = Properties["Username"]
  local password = Properties["Password"]
  if not IsEmpty(username) then
    log:debug("Setting MQTT credentials for user: %s", username)
    MQTT:SetUsernameAndPassword(username, password or "")
  end

  -- Set up callbacks
  MQTT:OnConnect(function(obj, reasonCode, flags, message)
    log:info("MQTT:OnConnect reasonCode=%s message=%s", reasonCode, message or "")
    if reasonCode == 0 then
      MQTT_CONNECTED = true
      updateStatus("Connected")

      -- Re-subscribe to all tracked topics
      for topic, bindings in pairs(subscriptions) do
        if next(bindings) then
          log:debug("Re-subscribing to topic: %s", topic)
          MQTT:Subscribe(topic)
        end
      end

      -- Notify child drivers
      notifyChildDrivers("BROKER_CONNECTED", {})
    else
      local errorMessage = message or MQTT:ReasonCodeToString(reasonCode) or "unknown"
      updateStatus("Connect failed: " .. errorMessage)
      log:error("MQTT connection failed: %s", errorMessage)

      -- Schedule reconnect
      SetTimer("reconnect", 30 * ONE_SECOND, function()
        Connect()
      end)
    end
  end)

  MQTT:OnDisconnect(function(obj, reasonCode)
    local reasonString = MQTT and MQTT:ReasonCodeToString(reasonCode) or "unknown"
    log:warn("MQTT:OnDisconnect reasonCode=%s - %s", reasonCode, reasonString)
    MQTT_CONNECTED = false
    updateStatus("Disconnected")

    -- Notify child drivers
    notifyChildDrivers("BROKER_DISCONNECTED", {})

    -- Schedule reconnect
    SetTimer("reconnect", 30 * ONE_SECOND, function()
      Connect()
    end)
  end)

  MQTT:OnMessage(function(obj, msgId, topic, payload, qos, retain)
    log:debug("MQTT:OnMessage msgId=%s topic=%s payload=%s qos=%s retain=%s", msgId, topic, payload, qos, retain)
    -- Cache the last message for new subscribers
    lastMessages[topic] = {
      payload = payload,
      qos = qos,
      retain = retain,
    }
    routeMessageToSubscribers(topic, payload, qos, retain)
  end)

  MQTT:OnPublish(function(obj, msgId, reasonCode)
    if reasonCode ~= 0 then
      local errorString = MQTT and MQTT:ErrorCodeToString(reasonCode) or "unknown"
      log:error("MQTT:Publish error msgId=%s: %s - %s", msgId, reasonCode, errorString)
    else
      log:trace("MQTT:Publish success msgId=%s", msgId)
    end
  end)

  MQTT:OnSubscribe(function(obj, msgId, grantedQos)
    log:debug("MQTT:OnSubscribe msgId=%s grantedQos=%s", msgId, grantedQos)
  end)

  updateStatus("Connecting...")
  local keepAlive = tonumber(Properties["Keep Alive"]) or 60
  log:info("Connecting to MQTT broker at %s:%s (keepAlive=%s)", brokerAddress, port, keepAlive)

  -- Defer connection slightly to allow any lingering connections to clean up
  SetTimer("mqtt_connect", ONE_SECOND, function()
    if MQTT then
      MQTT:Connect(brokerAddress, port, keepAlive)
    end
  end)
end

-- Handle SUBSCRIBE command from child drivers
function RFP.SUBSCRIBE(idBinding, strCommand, tParams, args)
  log:trace("RFP.SUBSCRIBE(%s, %s, %s, %s)", idBinding, strCommand, tParams, args)
  local topic = Select(tParams, "topic")
  local deviceId = tonumber(Select(tParams, "device_id"))
  local qos = tonumber(Select(tParams, "qos")) or 0

  if IsEmpty(topic) then
    log:warn("SUBSCRIBE called with empty topic")
    return
  end

  if not deviceId then
    log:warn("SUBSCRIBE called without device_id")
    return
  end

  -- Track subscription by device ID
  subscriptions[topic] = subscriptions[topic] or {}
  local isNewTopicSubscription = not next(subscriptions[topic])
  subscriptions[topic][deviceId] = true

  log:debug("Registered subscription: device=%s topic=%s", deviceId, topic)

  -- Subscribe to MQTT broker if this is a new topic
  if MQTT_CONNECTED and MQTT and isNewTopicSubscription then
    log:debug("Subscribing to topic: %s (qos=%s)", topic, qos)
    MQTT:Subscribe(topic, qos)
  elseif not isNewTopicSubscription then
    -- Send cached message to new subscriber (broker won't re-send retained messages)
    local cached = lastMessages[topic]
    if cached then
      log:debug("Sending cached message to new subscriber: device=%s topic=%s", deviceId, topic)
      SendToDevice(deviceId, "MQTT_MESSAGE", {
        topic = topic,
        payload = cached.payload,
        qos = tostring(cached.qos),
        retain = cached.retain and "true" or "false",
      })
    end
  end
end

-- Handle PUBLISH command from child drivers
function RFP.PUBLISH(idBinding, strCommand, tParams, args)
  log:trace("RFP.PUBLISH(%s, %s, %s, %s)", idBinding, strCommand, tParams, args)

  if not MQTT_CONNECTED or not MQTT then
    log:warn("Cannot publish - not connected to MQTT broker")
    return
  end

  local topic = Select(tParams, "topic")
  local payload = Select(tParams, "payload") or ""
  local qos = tonumber(Select(tParams, "qos")) or 0
  local retain = toboolean(Select(tParams, "retain"))

  if IsEmpty(topic) then
    log:warn("PUBLISH called with empty topic")
    return
  end

  log:debug("Publishing to topic=%s payload=%s qos=%s retain=%s", topic, payload, qos, retain)
  local errCode = MQTT:Publish(topic, payload, qos, retain)
  if errCode ~= 0 then
    local errorString = MQTT:ErrorCodeToString(errCode) or "unknown"
    log:error("Publish failed: %s - %s", errCode, errorString)
  end
end

-- Handle UNSUBSCRIBE command from child drivers
function RFP.UNSUBSCRIBE(idBinding, strCommand, tParams, args)
  log:trace("RFP.UNSUBSCRIBE(%s, %s, %s, %s)", idBinding, strCommand, tParams, args)
  local topic = Select(tParams, "topic")
  local deviceId = tonumber(Select(tParams, "device_id"))

  if IsEmpty(topic) then
    log:warn("UNSUBSCRIBE called with empty topic")
    return
  end

  if not deviceId then
    log:warn("UNSUBSCRIBE called without device_id")
    return
  end

  if subscriptions[topic] then
    subscriptions[topic][deviceId] = nil
    log:debug("Unregistered subscription: device=%s topic=%s", deviceId, topic)

    -- Only unsubscribe from broker if no other devices need this topic
    if not next(subscriptions[topic]) then
      subscriptions[topic] = nil
      if MQTT_CONNECTED and MQTT then
        log:debug("Unsubscribing from topic: %s", topic)
        MQTT:Unsubscribe(topic)
      end
    end
  end
end

-- Handle GET_STATUS command from child drivers
function RFP.GET_STATUS(idBinding, strCommand, tParams, args)
  log:trace("RFP.GET_STATUS(%s, %s, %s, %s)", idBinding, strCommand, tParams, args)
  SendToProxy(idBinding, MQTT_CONNECTED and "BROKER_CONNECTED" or "BROKER_DISCONNECTED", {}, "NOTIFY")
end

-- Track binding connections
OBC[MQTT_BROKER_BINDING] = function(idBinding, strClass, bIsBound, otherDeviceId, otherBindingId)
  log:trace(
    "OBC[MQTT_BROKER_BINDING](%s, %s, %s, %s, %s)",
    idBinding,
    strClass,
    bIsBound,
    otherDeviceId,
    otherBindingId
  )

  if bIsBound then
    -- Send current status to newly connected driver via broadcast on our binding
    SendToProxy(idBinding, MQTT_CONNECTED and "BROKER_CONNECTED" or "BROKER_DISCONNECTED", {}, "NOTIFY")
  else
    -- Clean up subscriptions for this device
    for topic, devices in pairs(subscriptions) do
      devices[otherDeviceId] = nil
      if IsEmpty(devices) then
        subscriptions[topic] = nil
        if MQTT_CONNECTED and MQTT then
          MQTT:Unsubscribe(topic)
        end
      end
    end
  end
end

-- Action: Reconnect
function EC.Reconnect()
  log:trace("EC.Reconnect()")
  log:print("Reconnecting to MQTT broker")
  Connect()
end

--#ifndef DRIVERCENTRAL
-- Action: Update Drivers
function EC.UpdateDrivers()
  log:trace("EC.UpdateDrivers()")
  log:print("Updating drivers")
  UpdateDrivers(true)
end

--- Update the driver from the GitHub repository.
--- @param forceUpdate? boolean Force the update even if the driver is up to date (optional).
function UpdateDrivers(forceUpdate)
  log:trace("UpdateDrivers(%s)", forceUpdate)
  githubUpdater
    :updateAll(DRIVER_GITHUB_REPO, DRIVER_FILENAMES, Properties["Update Channel"] == "Prerelease", forceUpdate)
    :next(function(updatedDrivers)
      if not IsEmpty(updatedDrivers) then
        log:info("Updated driver(s): %s", table.concat(updatedDrivers, ","))
      else
        log:info("No driver updates available")
      end
    end, function(error)
      log:error("An error occurred updating drivers: %s", error)
    end)
end
--#endif
