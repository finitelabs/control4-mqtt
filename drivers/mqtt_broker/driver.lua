--- MQTT Broker Driver
--- Owns a single client connection to an MQTT broker.
---
--- MQTT Universal drivers bound to its MQTT Broker connection subscribe, publish and unsubscribe through it, and get
--- each message on the topics they follow. A driver that subscribes to a topic the broker already follows gets the
--- topic's last message, marked retained.

--#ifndef DRIVERCENTRAL
DRIVER_GITHUB_REPO = "finitelabs/control4-mqtt"
--#endif

require("lib.utils")
require("drivers-common-public.global.handlers")
require("drivers-common-public.global.lib")
require("drivers-common-public.global.timer")

JSON = require("JSON")

local log = require("lib.logging")
local updateSettings = require("lib.update-settings")
--#ifdef DRIVERCENTRAL
local drivercentral = require("lib.drivercentral")
local supportCode = require("lib.support-code")
local diagnostics = require("lib.diagnostics")
--#endif
--#ifndef DRIVERCENTRAL
local githubUpdater = require("lib.github-updater")
local driverFilenames = require("lib.driver-filenames")
--#endif

local MQTT_BROKER_BINDING = 5001

local mqttClient = nil
local isBrokerConnected = false

-- Track subscriptions: topic -> {deviceId -> true}
local subscriptions = {}

-- Cache last message per topic for new subscribers
local lastMessages = {}

--- Defined with the connection code below; the lifecycle and property handlers need it first.
local connect

--#ifndef DRIVERCENTRAL
--- Get all MQTT driver instances sorted by device ID
--- @return integer[] deviceIds Sorted list of device IDs
local function getMQTTDriverIds()
  local drivers = C4:GetDevicesByC4iName(C4:GetDriverFileName()) or {}
  --- @type integer[]
  local ids = {}
  for id, _ in pairs(drivers) do
    table.insert(ids, tointeger(id))
  end
  table.sort(ids)
  return ids
end
--#endif

-----------------------------------------------------------------------
-- Driver lifecycle
-----------------------------------------------------------------------

function OnDriverInit()
  --#ifdef DRIVERCENTRAL
  drivercentral:startClient()
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

  -- Fire OnPropertyChanged to set the initial Headers and other Property
  -- global sets, they'll change if Property is changed.
  for p, _ in pairs(Properties) do
    local status, err = pcall(OnPropertyChanged, p)
    if not status and err then
      log:error("Error in OnPropertyChanged for property '%s': %s", p, err or "unknown error")
      --#ifdef DRIVERCENTRAL
      diagnostics:captureError(tostring(err), nil, "MQTTBroker.OnPropertyChanged")
      --#endif
    end
  end
  --#ifndef DRIVERCENTRAL
  -- Periodic update check (every 30 minutes, leader instance only)
  SetTimer("UpdateCheck", 30 * ONE_MINUTE, function()
    -- Recompute leader each cycle in case the previous leader was removed
    local isLeaderInstance = Select(getMQTTDriverIds(), 1) == C4:GetDeviceID()
    if isLeaderInstance and toboolean(Properties["Automatic Updates"]) then
      log:info("Checking for driver update (leader instance)")
      UpdateDrivers()
    end
  end, true)
  --#endif

  gInitialized = true
  connect()
  --#ifdef DRIVERCENTRAL
  -- connect() refuses while the gate holds the broker stopped, and reconnects once a license is back.
  drivercentral:startGate(function(licensed)
    log:info(licensed and "License active; connecting to the broker" or "No active license; disconnecting the broker")
    connect()
  end)
  --#endif
end

--#ifdef DRIVERCENTRAL
OnDriverLateInit = diagnostics:wrapLateInit(OnDriverLateInit)
--#endif

-----------------------------------------------------------------------
-- Property change handlers
-----------------------------------------------------------------------

function OPC.Driver_Status(propertyValue)
  log:trace("OPC.Driver_Status('%s')", propertyValue)
  if not gInitialized then
    UpdateProperty("Driver Status", "Initializing...", false)
    return
  end
end

function OPC.Automatic_Updates(propertyValue)
  log:trace("OPC.Automatic_Updates('%s')", propertyValue)
  if gInitialized then
    updateSettings:share("Automatic Updates", propertyValue)
  end
end

--#ifndef DRIVERCENTRAL
function OPC.Update_Channel(propertyValue)
  log:trace("OPC.Update_Channel('%s')", propertyValue)
  if gInitialized then
    updateSettings:share("Update Channel", propertyValue)
  end
end
--#endif

--- An update setting changed on another item.
function EC.SET_UPDATE_SETTING(params)
  log:trace("EC.SET_UPDATE_SETTING(%s)", params)
  updateSettings:take(params)
end

--#ifdef DRIVERCENTRAL
--- Not logged: the value is the code.
function OPC.Support_Code(propertyValue)
  supportCode:enter(propertyValue)
end

--- Turns Cloud Monitoring on or off.
--- @param propertyValue string
function OPC.Cloud_Monitoring(propertyValue)
  diagnostics:setEnabled(propertyValue == "Enabled")
end

--- Prints a diagnostics report, and sends it while Cloud Monitoring is on.
function EC.DiagnosticsSnapshot()
  diagnostics:dumpSnapshot()
end
--#endif

function OPC.Driver_Version(propertyValue)
  log:trace("OPC.Driver_Version('%s')", propertyValue)
  C4:UpdateProperty("Driver Version", C4:GetDriverConfigInfo("version"))
end

function OPC.Log_Mode(propertyValue)
  log:trace("OPC.Log_Mode('%s')", propertyValue)
  log:setLogMode(propertyValue)
  CancelTimer("LogMode")
  if not log:isEnabled() then
    UpdateProperty("Log Level", "3 - Info", true)
    return
  end
  log:warn("Log mode '%s' will expire in 3 hours", propertyValue)
  SetTimer("LogMode", 3 * ONE_HOUR, function()
    log:warn("Setting log mode to 'Off' (timer expired)")
    UpdateProperty("Log Mode", "Off", true)
  end)
  OnPropertyChanged("Log Level")
end

function OPC.Log_Level(propertyValue)
  log:trace("OPC.Log_Level('%s')", propertyValue)
  log:setLogLevel(propertyValue)
  if log:getLogLevel() >= 6 and log:isPrintEnabled() then
    DEBUGPRINT = true
    DEBUG_TIMER = true
    DEBUG_RFN = true
    DEBUG_URL = true
    DEBUG_WEBSOCKET = true
  else
    DEBUGPRINT = false
    DEBUG_TIMER = false
    DEBUG_RFN = false
    DEBUG_URL = false
    DEBUG_WEBSOCKET = false
  end
end

function OPC.Broker_Address(propertyValue)
  log:trace("OPC.Broker_Address('%s')", propertyValue)
  connect()
end

function OPC.Port(propertyValue)
  log:trace("OPC.Port('%s')", propertyValue)
  connect()
end

function OPC.Username(propertyValue)
  log:trace("OPC.Username('%s')", propertyValue)
  connect()
end

OPC.suppressDebug["Password"] = true
function OPC.Password(propertyValue)
  log:trace("OPC.Password('%s')", not IsEmpty(propertyValue) and "****" or "")
  connect()
end

function OPC.Keep_Alive(propertyValue)
  log:trace("OPC.Keep_Alive('%s')", propertyValue)
  connect()
end

-----------------------------------------------------------------------
-- Connection management
-----------------------------------------------------------------------

local function updateStatus(status)
  log:trace("updateStatus(%s)", status)
  UpdateProperty("Driver Status", not IsEmpty(status) and status or "Unknown")
end

--- Test condition for MQTT broker connection status
--- @param strConditionName string The name of the condition
--- @param tParams table Parameters for the condition test
--- @return boolean result True if the condition is met
function TC.BROKER_CONNECTED(strConditionName, tParams)
  log:trace("TC.BROKER_CONNECTED(%s, %s)", strConditionName, tParams)
  local test = Select(tParams, "VALUE") == "Connected"
  if Select(tParams, "LOGIC") == "NOT_EQUAL" then
    return test ~= isBrokerConnected
  else
    return test == isBrokerConnected
  end
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

  local devices = subscriptions[topic]
  if not IsEmpty(devices) then
    for deviceId, _ in pairs(devices) do
      log:debug("Routing message to device %s", deviceId)
      SendToDevice(deviceId, "MQTT_MESSAGE", {
        topic = topic,
        payload = payload,
        qos = tostring(qos),
        retain = retain and "true" or "false",
      })
    end
  end
end

--- The client's connect callback.
--- @param client userdata The client that called back.
--- @param reasonCode integer 0 when the broker accepted the connection.
--- @param _flags integer
--- @param message? string What the reason code means.
local function onConnect(client, reasonCode, _flags, message)
  -- A client replaced by a later connect() still calls back; acting on it would
  -- overwrite the new session's state.
  if client ~= mqttClient then
    log:debug("Ignoring stale OnConnect from replaced client")
    return
  end
  log:info("MQTT:OnConnect reasonCode=%s message=%s", reasonCode, message or "")
  if reasonCode == 0 then
    -- A reconnect armed before this session came up would tear it down
    CancelTimer("reconnect")

    isBrokerConnected = true
    updateStatus("Connected")
    C4:FireEvent("Broker Connected")

    for topic, bindings in pairs(subscriptions) do
      if next(bindings) then
        log:debug("Re-subscribing to topic: %s", topic)
        client:Subscribe(topic)
      end
    end

    notifyChildDrivers("BROKER_CONNECTED", {})
  else
    local errorMessage = message or client:ReasonCodeToString(reasonCode) or "unknown"
    updateStatus("Connect failed: " .. errorMessage)
    log:error("MQTT connection failed: %s", errorMessage)

    SetTimer("reconnect", 30 * ONE_SECOND, function()
      connect()
    end)
  end
end

--- The client's disconnect callback.
--- @param client userdata The client that called back.
--- @param reasonCode integer 0 for a clean close.
local function onDisconnect(client, reasonCode)
  -- Same stale-client guard as onConnect: the replaced client's own Disconnect() lands here.
  if client ~= mqttClient then
    log:debug("Ignoring stale OnDisconnect from replaced client")
    return
  end
  local reasonString = client:ReasonCodeToString(reasonCode) or "unknown"
  log:warn("MQTT:OnDisconnect reasonCode=%s - %s", reasonCode, reasonString)
  isBrokerConnected = false
  updateStatus("Disconnected")
  C4:FireEvent("Broker Disconnected")

  notifyChildDrivers("BROKER_DISCONNECTED", {})

  -- A server's clean close (reasonCode 0) isn't retried, so a broker that
  -- closes the connection on purpose isn't hammered.
  if reasonCode ~= 0 then
    SetTimer("reconnect", 30 * ONE_SECOND, function()
      connect()
    end)
  end
end

--- The client's message callback.
local function onMessage(_client, msgId, topic, payload, qos, retain)
  log:debug("MQTT:OnMessage msgId=%s topic=%s payload=%s qos=%s retain=%s", msgId, topic, payload, qos, retain)
  lastMessages[topic] = {
    payload = payload,
    qos = qos,
  }
  routeMessageToSubscribers(topic, payload, qos, retain)
end

--- The client's publish callback.
local function onPublish(client, msgId, reasonCode)
  if reasonCode ~= 0 then
    local errorString = client:ErrorCodeToString(reasonCode) or "unknown"
    log:error("MQTT:Publish error msgId=%s: %s - %s", msgId, reasonCode, errorString)
  else
    log:trace("MQTT:Publish success msgId=%s", msgId)
  end
end

--- The client's subscribe callback.
local function onSubscribe(_client, msgId, grantedQos)
  log:debug("MQTT:OnSubscribe msgId=%s grantedQos=%s", msgId, grantedQos)
end

--#ifdef DRIVERCENTRAL
-- The client calls these directly, with no dispatcher to report an error.
onConnect = diagnostics:wrap(onConnect, "MQTTBroker.OnConnect")
onDisconnect = diagnostics:wrap(onDisconnect, "MQTTBroker.OnDisconnect")
onMessage = diagnostics:wrap(onMessage, "MQTTBroker.OnMessage")
onPublish = diagnostics:wrap(onPublish, "MQTTBroker.OnPublish")
onSubscribe = diagnostics:wrap(onSubscribe, "MQTTBroker.OnSubscribe")
--#endif

--- (Re)connects to the broker from the properties, replacing any client.
connect = function()
  log:trace("connect()")
  if not gInitialized then
    updateStatus("Initializing...")
    return
  end

  CancelTimer("reconnect")

  -- Tell bound items the connection is going down before reconnecting
  notifyChildDrivers("BROKER_DISCONNECTED", {})

  if mqttClient then
    log:debug("Disconnecting existing MQTT connection")
    mqttClient:Disconnect()
    mqttClient = nil
  end
  isBrokerConnected = false

  local brokerAddress = Properties["Broker Address"]
  local port = tonumber(Properties["Port"]) or 1883

  if IsEmpty(brokerAddress) then
    updateStatus("Not configured")
    return
  end

  --#ifdef DRIVERCENTRAL
  if not drivercentral:licensed() then
    updateStatus(drivercentral.UNLICENSED_STATUS)
    return
  end
  --#endif

  local clientId = "control4-mqtt-device-" .. C4:GetDeviceID()
  log:info("Creating MQTT client with clientId: %s", clientId)
  mqttClient = C4:MQTT(clientId)

  local username = Properties["Username"]
  local password = Properties["Password"]
  if not IsEmpty(username) then
    log:debug("Setting MQTT credentials for user: %s", username)
    mqttClient:SetUsernameAndPassword(username, password or "")
  end

  mqttClient:OnConnect(onConnect)
  mqttClient:OnDisconnect(onDisconnect)
  mqttClient:OnMessage(onMessage)
  mqttClient:OnPublish(onPublish)
  mqttClient:OnSubscribe(onSubscribe)

  updateStatus("Connecting...")
  local keepAlive = tonumber(Properties["Keep Alive"]) or 60
  log:info("Connecting to MQTT broker at %s:%s (keepAlive=%s)", brokerAddress, port, keepAlive)
  mqttClient:Connect(brokerAddress, port, keepAlive)
end

-----------------------------------------------------------------------
-- Receive From Proxy (RFP) handlers
-----------------------------------------------------------------------

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

  subscriptions[topic] = subscriptions[topic] or {}
  local isNewTopicSubscription = not next(subscriptions[topic])
  subscriptions[topic][deviceId] = true

  log:debug("Registered subscription: device=%s topic=%s", deviceId, topic)

  -- Subscribe to MQTT broker if this is a new topic
  if isBrokerConnected and mqttClient and isNewTopicSubscription then
    log:debug("Subscribing to topic: %s (qos=%s)", topic, qos)
    mqttClient:Subscribe(topic, qos)
  elseif not isNewTopicSubscription then
    -- Send cached message to new subscriber (broker won't re-send retained messages).
    -- Marked retained, as a broker marks what it sends because of a new subscription.
    local cached = lastMessages[topic]
    if cached then
      log:debug("Sending cached message to new subscriber: device=%s topic=%s", deviceId, topic)
      SendToDevice(deviceId, "MQTT_MESSAGE", {
        topic = topic,
        payload = cached.payload,
        qos = tostring(cached.qos),
        retain = "true",
      })
    end
  end
end

function RFP.PUBLISH(idBinding, strCommand, tParams, args)
  log:trace("RFP.PUBLISH(%s, %s, %s, %s)", idBinding, strCommand, tParams, args)

  if not isBrokerConnected or not mqttClient then
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
  local errCode = mqttClient:Publish(topic, payload, qos, retain)
  if errCode ~= 0 then
    local errorString = mqttClient:ErrorCodeToString(errCode) or "unknown"
    log:error("Publish failed: %s - %s", errCode, errorString)
  end
end

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
      if isBrokerConnected and mqttClient then
        log:debug("Unsubscribing from topic: %s", topic)
        mqttClient:Unsubscribe(topic)
      end
    end
  end
end

function RFP.GET_STATUS(idBinding, strCommand, tParams, args)
  log:trace("RFP.GET_STATUS(%s, %s, %s, %s)", idBinding, strCommand, tParams, args)
  SendToProxy(idBinding, isBrokerConnected and "BROKER_CONNECTED" or "BROKER_DISCONNECTED", {}, "NOTIFY")
end

-----------------------------------------------------------------------
-- On Binding Changed (OBC) handler
-----------------------------------------------------------------------

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
    -- Send current status to the newly bound driver
    SendToProxy(idBinding, isBrokerConnected and "BROKER_CONNECTED" or "BROKER_DISCONNECTED", {}, "NOTIFY")
  else
    -- Clean up subscriptions for this device
    for topic, devices in pairs(subscriptions) do
      devices[otherDeviceId] = nil
      if IsEmpty(devices) then
        subscriptions[topic] = nil
        if isBrokerConnected and mqttClient then
          mqttClient:Unsubscribe(topic)
        end
      end
    end
  end
end

-----------------------------------------------------------------------
-- Execute Command (EC) handlers
-----------------------------------------------------------------------

function EC.Reconnect()
  log:trace("EC.Reconnect()")
  log:print("Reconnecting to MQTT broker")
  connect()
end

--#ifndef DRIVERCENTRAL
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
    :updateAll(DRIVER_GITHUB_REPO, driverFilenames, Properties["Update Channel"] == "Prerelease", forceUpdate)
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
