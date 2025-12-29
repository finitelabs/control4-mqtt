--#ifdef DRIVERCENTRAL
DC_PID = 857
DC_X = nil
DC_FILENAME = "mqtt_button.c4z"
--#endif
require("lib.utils")
require("vendor.drivers-common-public.global.handlers")
require("vendor.drivers-common-public.global.lib")
require("vendor.drivers-common-public.global.timer")

local log = require("lib.logging")

-- Binding IDs
local MQTT_BINDING = 5001

-- Whether the broker is connected
local BROKER_CONNECTED = false

-- Whether the device is available (from availability topic)
local DEVICE_AVAILABLE = true

-- Cached payload for re-evaluation when properties change
local LAST_AVAILABILITY_PAYLOAD = nil

-- Previous topic (for unsubscribing when changed)
local PREVIOUS_AVAILABILITY_TOPIC = nil

-----------------------------------------------------------------------
-- Local helper functions
-----------------------------------------------------------------------

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

--- Update subscription to availability topic
local function updateSubscriptions()
  log:trace("updateSubscriptions()")
  local availabilityTopic = Properties["Availability Topic"]
  local qos = Properties["QoS"] or "0"
  local deviceId = tostring(C4:GetDeviceID())

  -- Unsubscribe from previous availability topic if changed
  if PREVIOUS_AVAILABILITY_TOPIC and PREVIOUS_AVAILABILITY_TOPIC ~= availabilityTopic then
    log:debug("Unsubscribing from previous availability topic: %s", PREVIOUS_AVAILABILITY_TOPIC)
    SendToProxy(MQTT_BINDING, "UNSUBSCRIBE", { topic = PREVIOUS_AVAILABILITY_TOPIC, device_id = deviceId })
  end

  -- Subscribe to new topic if configured and broker is connected
  if BROKER_CONNECTED and not IsEmpty(availabilityTopic) then
    log:debug("Subscribing to availability topic: %s (qos=%s)", availabilityTopic, qos)
    SendToProxy(MQTT_BINDING, "SUBSCRIBE", { topic = availabilityTopic, qos = qos, device_id = deviceId })
  end

  PREVIOUS_AVAILABILITY_TOPIC = availabilityTopic
end

--- Publish the press command to the MQTT broker
local function press()
  log:trace("press()")
  local commandTopic = Properties["Command Topic"]
  if IsEmpty(commandTopic) then
    log:warn("Cannot publish - Command Topic not configured")
    return
  end

  if not BROKER_CONNECTED then
    log:warn("Cannot publish - broker not connected")
    return
  end

  local payload = Properties["Payload Press"] or "PRESS"
  local qos = Properties["QoS"] or "0"
  local retain = Properties["Retain"] == "Yes" and "true" or "false"

  log:info("Button pressed: topic=%s payload=%s", commandTopic, payload)

  SendToProxy(MQTT_BINDING, "PUBLISH", {
    topic = commandTopic,
    payload = payload,
    qos = qos,
    retain = retain,
  })
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

function OPC.Payload_Press(propertyValue)
  log:trace("OPC.Payload_Press('%s')", propertyValue)
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

function OPC.QoS(propertyValue)
  log:trace("OPC.QoS('%s')", propertyValue)
end

function OPC.Retain(propertyValue)
  log:trace("OPC.Retain('%s')", propertyValue)
end

-----------------------------------------------------------------------
-- Receive From Proxy (RFP) handlers
-----------------------------------------------------------------------

-- Handle BROKER_CONNECTED from MQTT broker
function RFP.BROKER_CONNECTED(idBinding, strCommand, tParams, args)
  log:trace("RFP.BROKER_CONNECTED(%s, %s, %s, %s)", idBinding, strCommand, tParams, args)
  if idBinding ~= MQTT_BINDING then
    return
  end

  log:info("MQTT broker connected")
  BROKER_CONNECTED = true

  -- Subscribe to availability topic
  updateSubscriptions()

  -- Update status
  if IsEmpty(Properties["Availability Topic"]) then
    UpdateProperty("Driver Status", "Connected (no availability topic)")
  else
    UpdateProperty("Driver Status", "Connected")
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
  BROKER_CONNECTED = false
  DEVICE_AVAILABLE = true
  PREVIOUS_AVAILABILITY_TOPIC = nil
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

-- Handle Press action from Composer programming
function EC.Press()
  log:trace("EC.Press()")
  press()
end

-- Handle MQTT_MESSAGE from broker via C4:SendToDevice
function EC.MQTT_MESSAGE(tParams)
  log:trace("EC.MQTT_MESSAGE(%s)", tParams)

  local topic = Select(tParams, "topic")
  local payload = Select(tParams, "payload")

  log:debug("Received targeted MQTT message: topic=%s payload=%s", topic, payload)

  local availabilityTopic = Properties["Availability Topic"]

  -- Check if this is the availability topic
  if topic == availabilityTopic then
    -- Cache payload for re-evaluation when properties change
    LAST_AVAILABILITY_PAYLOAD = payload
    reevaluateAvailability()
    return
  end

  log:trace("Ignoring message for topic %s", topic)
end
