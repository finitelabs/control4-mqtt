--#ifdef DRIVERCENTRAL
DC_PID = 857
DC_X = nil
DC_FILENAME = "mqtt_switch.c4z"
--#endif
require("lib.utils")
require("vendor.drivers-common-public.global.handlers")
require("vendor.drivers-common-public.global.lib")
require("vendor.drivers-common-public.global.timer")

local log = require("lib.logging")

-- Binding IDs
local PROXY_BINDING = 5001
local MQTT_BINDING = 5002

-- Current state (nil = unknown, true = on, false = off)
local STATE = nil

-- Whether the broker is connected
local BROKER_CONNECTED = false

-- Whether the device is available (from availability topic)
local DEVICE_AVAILABLE = true

-- Cached payloads for re-evaluation when properties change
local LAST_STATE_PAYLOAD = nil
local LAST_AVAILABILITY_PAYLOAD = nil

-- Previous topics (for unsubscribing when changed)
local PREVIOUS_STATE_TOPIC = nil
local PREVIOUS_AVAILABILITY_TOPIC = nil

-----------------------------------------------------------------------
-- Local helper functions
-----------------------------------------------------------------------

--- Update the switch state and notify Control4
--- @param newState boolean The new state (true = on, false = off)
local function updateState(newState)
  log:trace("updateState(%s)", newState)
  if STATE == newState then
    return
  end

  log:info("State changed: %s -> %s", STATE, newState)
  STATE = newState

  -- Send relay state notification (CLOSED = on, OPENED = off)
  SendToProxy(PROXY_BINDING, newState and "CLOSED" or "OPENED", {}, "NOTIFY")
end

--- Update device availability
--- @param available boolean Whether the device is available
local function updateAvailability(available)
  log:trace("updateAvailability(%s)", available)
  if DEVICE_AVAILABLE == available then
    return
  end

  log:info("Availability changed: %s -> %s", DEVICE_AVAILABLE, available)
  DEVICE_AVAILABLE = available

  if available then
    UpdateProperty("Driver Status", "Connected")
  else
    UpdateProperty("Driver Status", "Device unavailable")
  end
end

--- Check if we should use optimistic mode
--- @return boolean True if optimistic mode is enabled
local function isOptimistic()
  log:trace("isOptimistic()")
  local optimistic = Properties["Optimistic"]
  if optimistic == "Yes" then
    return true
  elseif optimistic == "No" then
    return false
  else
    -- Auto: optimistic if no state topic
    return IsEmpty(Properties["State Topic"])
  end
end

--- Publish a command to the MQTT broker
--- @param state boolean The desired state (true = on, false = off)
local function publishCommand(state)
  log:trace("publishCommand(%s)", state)
  local commandTopic = Properties["Command Topic"]
  if IsEmpty(commandTopic) then
    log:warn("Cannot publish - Command Topic not configured")
    return
  end

  if not BROKER_CONNECTED then
    log:warn("Cannot publish - broker not connected")
    return
  end

  local payload = state and Properties["Payload On"] or Properties["Payload Off"]
  local qos = Properties["QoS"] or "0"
  local retain = Properties["Retain"] == "Yes" and "true" or "false"

  log:debug("Publishing command: topic=%s payload=%s qos=%s retain=%s", commandTopic, payload, qos, retain)

  SendToProxy(MQTT_BINDING, "PUBLISH", {
    topic = commandTopic,
    payload = payload,
    qos = qos,
    retain = retain,
  })

  -- Optimistic update
  if isOptimistic() then
    updateState(state)
  end
end

--- Turn the switch on
local function on()
  log:trace("on()")
  publishCommand(true)
end

--- Turn the switch off
local function off()
  log:trace("off()")
  publishCommand(false)
end

--- Toggle the switch
local function toggle()
  log:trace("toggle()")
  if STATE then
    off()
  else
    on()
  end
end

--- Update subscriptions to state and availability topics
local function updateSubscriptions()
  log:trace("updateSubscriptions()")
  local stateTopic = Properties["State Topic"]
  local availabilityTopic = Properties["Availability Topic"]
  local qos = Properties["QoS"] or "0"
  local deviceId = tostring(C4:GetDeviceID())

  -- Unsubscribe from previous state topic if changed
  if PREVIOUS_STATE_TOPIC and PREVIOUS_STATE_TOPIC ~= stateTopic then
    log:debug("Unsubscribing from previous state topic: %s", PREVIOUS_STATE_TOPIC)
    SendToProxy(MQTT_BINDING, "UNSUBSCRIBE", { topic = PREVIOUS_STATE_TOPIC, device_id = deviceId })
  end

  -- Unsubscribe from previous availability topic if changed
  if PREVIOUS_AVAILABILITY_TOPIC and PREVIOUS_AVAILABILITY_TOPIC ~= availabilityTopic then
    log:debug("Unsubscribing from previous availability topic: %s", PREVIOUS_AVAILABILITY_TOPIC)
    SendToProxy(MQTT_BINDING, "UNSUBSCRIBE", { topic = PREVIOUS_AVAILABILITY_TOPIC, device_id = deviceId })
  end

  -- Subscribe to new topics if configured and broker is connected
  if BROKER_CONNECTED then
    if not IsEmpty(stateTopic) then
      log:debug("Subscribing to state topic: %s (qos=%s)", stateTopic, qos)
      SendToProxy(MQTT_BINDING, "SUBSCRIBE", { topic = stateTopic, qos = qos, device_id = deviceId })
    end

    if not IsEmpty(availabilityTopic) then
      log:debug("Subscribing to availability topic: %s (qos=%s)", availabilityTopic, qos)
      SendToProxy(MQTT_BINDING, "SUBSCRIBE", { topic = availabilityTopic, qos = qos, device_id = deviceId })
    end
  end

  PREVIOUS_STATE_TOPIC = stateTopic
  PREVIOUS_AVAILABILITY_TOPIC = availabilityTopic
end

--- Re-evaluate state based on cached payload and current properties
local function reevaluateState()
  log:trace("reevaluateState()")
  if LAST_STATE_PAYLOAD == nil then
    return
  end

  -- Determine ON state payload
  local stateOn = Properties["State On"]
  if IsEmpty(stateOn) then
    stateOn = Properties["Payload On"]
  end

  -- Determine OFF state payload
  local stateOff = Properties["State Off"]
  if IsEmpty(stateOff) then
    stateOff = Properties["Payload Off"]
  end

  -- Update state based on cached payload
  if LAST_STATE_PAYLOAD == stateOn then
    updateState(true)
  elseif LAST_STATE_PAYLOAD == stateOff then
    updateState(false)
  else
    log:debug("Cached payload '%s' doesn't match new State On/Off values", LAST_STATE_PAYLOAD)
  end
end

--- Re-evaluate availability based on cached payload and current properties
local function reevaluateAvailability()
  log:trace("reevaluateAvailability()")
  if LAST_AVAILABILITY_PAYLOAD == nil then
    return
  end

  local payloadAvailable = Properties["Payload Available"] or "online"
  local payloadNotAvailable = Properties["Payload Not Available"] or "offline"

  if LAST_AVAILABILITY_PAYLOAD == payloadAvailable then
    updateAvailability(true)
  elseif LAST_AVAILABILITY_PAYLOAD == payloadNotAvailable then
    updateAvailability(false)
  else
    log:debug("Cached payload '%s' doesn't match availability values", LAST_AVAILABILITY_PAYLOAD)
  end
end

-----------------------------------------------------------------------
-- Driver lifecycle
-----------------------------------------------------------------------

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

  -- Fire OnPropertyChanged to set the initial Headers and other Property
  -- global sets, they'll change if Property is changed.
  for p, _ in pairs(Properties) do
    local status, err = pcall(OnPropertyChanged, p)
    if not status and err ~= nil then
      log:error(err)
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

function OPC.Driver_Status(propertyValue)
  log:trace("OPC.Driver_Status('%s')", propertyValue)
  if not gInitialized then
    UpdateProperty("Driver Status", "Initializing", false)
    return
  end
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

function OPC.Command_Topic(propertyValue)
  log:trace("OPC.Command_Topic('%s')", propertyValue)
end

function OPC.Payload_On(propertyValue)
  log:trace("OPC.Payload_On('%s')", propertyValue)
  -- Re-evaluate state in case State On is empty and defaults to Payload On
  reevaluateState()
end

function OPC.Payload_Off(propertyValue)
  log:trace("OPC.Payload_Off('%s')", propertyValue)
  -- Re-evaluate state in case State Off is empty and defaults to Payload Off
  reevaluateState()
end

function OPC.State_Topic(propertyValue)
  log:trace("OPC.State_Topic('%s')", propertyValue)
  -- Clear cached payload when topic changes (new topic = new payloads)
  LAST_STATE_PAYLOAD = nil
  updateSubscriptions()
end

function OPC.State_On(propertyValue)
  log:trace("OPC.State_On('%s')", propertyValue)
  reevaluateState()
end

function OPC.State_Off(propertyValue)
  log:trace("OPC.State_Off('%s')", propertyValue)
  reevaluateState()
end

function OPC.Availability_Topic(propertyValue)
  log:trace("OPC.Availability_Topic('%s')", propertyValue)
  -- Clear cached payload when topic changes
  LAST_AVAILABILITY_PAYLOAD = nil
  updateSubscriptions()
end

function OPC.Payload_Available(propertyValue)
  log:trace("OPC.Payload_Available('%s')", propertyValue)
  reevaluateAvailability()
end

function OPC.Payload_Not_Available(propertyValue)
  log:trace("OPC.Payload_Not_Available('%s')", propertyValue)
  reevaluateAvailability()
end

function OPC.Optimistic(propertyValue)
  log:trace("OPC.Optimistic('%s')", propertyValue)
end

function OPC.QoS(propertyValue)
  log:trace("OPC.QoS('%s')", propertyValue)
end

function OPC.Retain(propertyValue)
  log:trace("OPC.Retain('%s')", propertyValue)
end

-----------------------------------------------------------------------
-- Receive From Proxy (RFP) handlers
-----------------------------------------------------------------------

-- Handle ON command from relay proxy
function RFP.ON(idBinding, strCommand, tParams, args)
  log:trace("RFP.ON(%s, %s, %s, %s)", idBinding, strCommand, tParams, args)
  if idBinding ~= PROXY_BINDING then
    return
  end
  on()
end

-- Handle OFF command from relay proxy
function RFP.OFF(idBinding, strCommand, tParams, args)
  log:trace("RFP.OFF(%s, %s, %s, %s)", idBinding, strCommand, tParams, args)
  if idBinding ~= PROXY_BINDING then
    return
  end
  off()
end

-- Handle TOGGLE command from relay proxy
function RFP.TOGGLE(idBinding, strCommand, tParams, args)
  log:trace("RFP.TOGGLE(%s, %s, %s, %s)", idBinding, strCommand, tParams, args)
  if idBinding ~= PROXY_BINDING then
    return
  end
  toggle()
end

-- Handle CLOSE command from relay proxy (same as ON)
function RFP.CLOSE(idBinding, strCommand, tParams, args)
  log:trace("RFP.CLOSE(%s, %s, %s, %s)", idBinding, strCommand, tParams, args)
  if idBinding ~= PROXY_BINDING then
    return
  end
  on()
end

-- Handle OPEN command from relay proxy (same as OFF)
function RFP.OPEN(idBinding, strCommand, tParams, args)
  log:trace("RFP.OPEN(%s, %s, %s, %s)", idBinding, strCommand, tParams, args)
  if idBinding ~= PROXY_BINDING then
    return
  end
  off()
end

-- Handle TRIGGER command from relay proxy (pulse)
function RFP.TRIGGER(idBinding, strCommand, tParams, args)
  log:trace("RFP.TRIGGER(%s, %s, %s, %s)", idBinding, strCommand, tParams, args)
  if idBinding ~= PROXY_BINDING then
    return
  end

  local pulseTime = tonumber(Select(tParams, "TIME")) or 0
  on()

  if pulseTime > 0 then
    SetTimer("FinishPulse", pulseTime, function()
      log:debug("Turning off after pulse time of %dms", pulseTime)
      off()
    end)
  end
end

-- Handle BROKER_CONNECTED from MQTT broker
function RFP.BROKER_CONNECTED(idBinding, strCommand, tParams, args)
  log:trace("RFP.BROKER_CONNECTED(%s, %s, %s, %s)", idBinding, strCommand, tParams, args)
  if idBinding ~= MQTT_BINDING then
    return
  end

  log:info("MQTT broker connected")
  BROKER_CONNECTED = true

  -- Subscribe to topics
  updateSubscriptions()

  -- Update status
  local emptyTopics = {}
  if IsEmpty(Properties["State Topic"]) then
    table.insert(emptyTopics, "state")
  end
  if IsEmpty(Properties["Availability Topic"]) then
    table.insert(emptyTopics, "availability")
  end

  if IsEmpty(emptyTopics) then
    UpdateProperty("Driver Status", "Connected")
  else
    UpdateProperty(
      "Driver Status",
      "Connected (no "
        .. table.concat(emptyTopics, "/")
        .. " topic"
        .. (TableLength(emptyTopics) > 1 and "s" or "")
        .. ")"
    )
  end
end

-- Handle BROKER_DISCONNECTED from MQTT broker
function RFP.BROKER_DISCONNECTED(idBinding, strCommand, tParams, args)
  log:trace("RFP.BROKER_DISCONNECTED(%s, %s, %s, %s)", idBinding, strCommand, tParams, args)
  if idBinding ~= MQTT_BINDING then
    return
  end

  log:warn("MQTT broker disconnected")
  BROKER_CONNECTED = false
  UpdateProperty("Driver Status", "Disconnected")
end

-----------------------------------------------------------------------
-- On Binding Changed (OBC) handler
-----------------------------------------------------------------------

OBC[MQTT_BINDING] = function(idBinding, strClass, bIsBound, otherDeviceId, otherBindingId)
  log:trace("OBC[MQTT_BINDING](%s, %s, %s, %s, %s)", idBinding, strClass, bIsBound, otherDeviceId, otherBindingId)
  -- Reset state when binding is changed
  STATE = nil
  BROKER_CONNECTED = false
  DEVICE_AVAILABLE = true
  PREVIOUS_STATE_TOPIC = nil
  PREVIOUS_AVAILABILITY_TOPIC = nil
  LAST_STATE_PAYLOAD = nil
  LAST_AVAILABILITY_PAYLOAD = nil
  UpdateProperty("Driver Status", "Disconnected")
  if bIsBound then
    -- Request current broker status
    SendToProxy(MQTT_BINDING, "GET_STATUS", {}, "NOTIFY")
  end
end

-----------------------------------------------------------------------
-- Execute Command (EC) handlers
-----------------------------------------------------------------------

-- Handle On action from Composer programming
function EC.On()
  log:trace("EC.On()")
  on()
end

-- Handle Off action from Composer programming
function EC.Off()
  log:trace("EC.Off()")
  off()
end

-- Handle Toggle action from Composer programming
function EC.Toggle()
  log:trace("EC.Toggle()")
  toggle()
end

-- Handle MQTT_MESSAGE from broker via C4:SendToDevice
function EC.MQTT_MESSAGE(tParams)
  log:trace("EC.MQTT_MESSAGE(%s)", tParams)

  local topic = Select(tParams, "topic")
  local payload = Select(tParams, "payload")

  log:debug("Received targeted MQTT message: topic=%s payload=%s", topic, payload)

  local stateTopic = Properties["State Topic"]
  local availabilityTopic = Properties["Availability Topic"]

  -- Check if this is the state topic
  if topic == stateTopic then
    -- Cache payload for re-evaluation when properties change
    LAST_STATE_PAYLOAD = payload
    reevaluateState()
    return
  end

  -- Check if this is the availability topic
  if topic == availabilityTopic then
    -- Cache payload for re-evaluation when properties change
    LAST_AVAILABILITY_PAYLOAD = payload
    reevaluateAvailability()
    return
  end

  log:trace("Ignoring message for topic %s", topic)
end
