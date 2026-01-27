--- MQTT Universal Driver
--- A Control4 driver for integrating MQTT-based devices and variables.
---
--- This driver connects to an MQTT broker (via the MQTT Broker driver) and allows
--- dynamic creation of relays, contacts, buttons, and typed variables that communicate
--- over MQTT topics. Each item can be configured with state and command topics,
--- payload mappings, and JSONPath extraction for complex payloads.

--#ifdef DRIVERCENTRAL
DC_PID = 858
DC_X = nil
DC_FILENAME = "mqtt_universal.c4z"
--#endif
require("lib.utils")
require("vendor.drivers-common-public.global.handlers")
require("vendor.drivers-common-public.global.lib")
require("vendor.drivers-common-public.global.timer")

local bindings = require("lib.bindings")
local events = require("lib.events")
local log = require("lib.logging")
local persist = require("lib.persist")
local values = require("lib.values")

-- MQTT entity modules
local MqttDevice = require("mqtt.entities.device")
local MqttRelay = require("mqtt.entities.relay")
local MqttContact = require("mqtt.entities.contact")
local MqttButton = require("mqtt.entities.button")
local MqttEvent = require("mqtt.entities.event")
local MqttVariable = require("mqtt.entities.variable")
local MqttSensor = require("mqtt.entities.sensor")

local constants = require("constants")

-- Binding IDs
local MQTT_BINDING = 5001

-- Constants
local SELECT_OPTION = "(Select)"
local ITEMS_PERSIST_KEY = "Items"

-- Entity type mapping
local ENTITY_CLASSES = {
  RELAY = MqttRelay,
  CONTACT = MqttContact,
  BUTTON = MqttButton,
  EVENT = MqttEvent,
  STRING = MqttVariable,
  BOOL = MqttVariable,
  NUMBER = MqttVariable,
  FLOAT = MqttVariable,
  TEMPERATURE = MqttSensor,
  HUMIDITY = MqttSensor,
}

-- Runtime entity instances (keyed by item ID)
local entities = {}

-----------------------------------------------------------------------
-- Item storage functions
-----------------------------------------------------------------------

--- Get all items from persistent storage
--- @return table<string, table> Items indexed by ID
local function getItems()
  log:trace("getItems()")
  return persist:get(ITEMS_PERSIST_KEY, {}) or {}
end

--- Save items to persistent storage
--- @param items table<string, table> Items to save
local function saveItems(items)
  log:trace("saveItems(%s)", items)
  persist:set(ITEMS_PERSIST_KEY, not IsEmpty(items) and items or nil)
end

--- Get the next available item ID
--- @return number Next available ID
local function getNextItemId()
  log:trace("getNextItemId()")
  local items = getItems()
  local id = 1
  while items[tostring(id)] do
    id = id + 1
  end
  return id
end

--- Get a single item by ID
--- @param itemId string|number Item ID
--- @return table|nil Item data or nil if not found
local function getItem(itemId)
  log:trace("getItem(%s)", itemId)
  local items = getItems()
  return items[tostring(itemId)]
end

--- Parse item ID from display name format "Name (TYPE) [ID]"
--- @param displayName string Display name from dynamic list
--- @return string|nil Item ID or nil
local function parseItemId(displayName)
  log:trace("parseItemId(%s)", displayName)
  return string.match(displayName or "", "%[(%d+)%]$")
end

--- Get the currently selected item ID from the Configure Item property.
--- @return string|nil itemId The selected item ID, or nil if none selected.
local function getSelectedItemId()
  local propertyValue = Properties["Configure Item"]
  if IsEmpty(propertyValue) or propertyValue == SELECT_OPTION then
    return nil
  end
  return parseItemId(propertyValue)
end

--- Get the currently selected item for configuration.
--- @return table|nil Selected item or nil.
local function getSelectedItem()
  log:trace("getSelectedItem()")
  local itemId = getSelectedItemId()
  if itemId == nil then
    return nil
  end
  return getItem(itemId)
end

--- Get entity instance for an item
--- @param itemId string|number Item ID
--- @return MqttEntity|nil Entity instance or nil
local function getEntity(itemId)
  return entities[tostring(itemId)]
end

--- Get currently selected entity
--- @return MqttEntity|nil
local function getSelectedEntity()
  local itemId = getSelectedItemId()
  if itemId == nil then
    return nil
  end
  return getEntity(itemId)
end

--- Create an entity instance for an item
--- @param item table Item data
--- @return MqttEntity|nil Entity instance
local function createEntity(item)
  local EntityClass = ENTITY_CLASSES[item.itemType]
  if EntityClass == nil then
    log:warn("Unknown item type: %s", item.itemType)
    return nil
  end

  local entity = EntityClass:new(item, MQTT_BINDING)
  entities[tostring(item.id)] = entity
  return entity
end

--- Destroy an entity instance
--- @param itemId string|number Item ID
local function destroyEntity(itemId)
  local entity = entities[tostring(itemId)]
  if entity then
    entity:reset()
    entities[tostring(itemId)] = nil
  end
end

-----------------------------------------------------------------------
-- Subscription management
-----------------------------------------------------------------------

--- Subscribe to topics for an entity
--- @param entity MqttEntity Entity instance
local function subscribeEntity(entity)
  if not MqttDevice:isConnected() then
    return
  end
  local deviceId = tostring(C4:GetDeviceID())
  entity:subscribe(deviceId)
end

--- Subscribe to all entity topics
local function subscribeAllEntities()
  log:trace("subscribeAllEntities()")
  for _, entity in pairs(entities) do
    subscribeEntity(entity)
  end

  -- Subscribe to availability
  local availabilityTopic = Properties["Availability Topic"]
  local deviceId = tostring(C4:GetDeviceID())
  MqttDevice:subscribeToAvailability(availabilityTopic, deviceId)
end

-----------------------------------------------------------------------
-- Item management
-----------------------------------------------------------------------

--- Add a new item
--- Check if an item with the given name already exists.
--- @param name string Item name to check.
--- @return boolean exists True if an item with this name exists.
local function itemNameExists(name)
  local items = getItems()
  for _, item in pairs(items) do
    if item.name == name then
      return true
    end
  end
  return false
end

--- @param name string Item name
--- @param itemType string Item type
--- @return string|nil Item ID, or nil if name already exists
local function addItem(name, itemType)
  log:trace("addItem(%s, %s)", name, itemType)

  -- Validate unique name
  if itemNameExists(name) then
    log:print("Item with name '%s' already exists", name)
    return nil
  end

  local items = getItems()
  local itemId = getNextItemId()
  local displayName = name .. " (" .. itemType .. ") [" .. itemId .. "]"

  local itemData = {
    id = itemId,
    name = name,
    itemType = itemType,
    displayName = displayName,
    stateTopic = "",
    commandTopic = "",
    qos = "0",
    retain = false,
    -- Relay-specific (no defaults - user must set at least one payload/state)
    payloadOn = "",
    payloadOff = "",
    stateOn = "",
    stateOff = "",
    optimistic = "Auto",
    -- Contact-specific (no defaults - user must set at least one state)
    stateOpen = "",
    stateClosed = "",
    -- Button-specific (no default - user must set payload)
    payloadPress = "",
    -- Event-specific (no default - user sets filter if needed)
    eventTypeFilter = "",
    -- Temperature-specific defaults
    temperatureScale = "Celsius",
    -- JSONPath value extraction
    valuePath = "",
  }

  items[tostring(itemId)] = itemData
  saveItems(items)

  -- Create entity instance
  local entity = createEntity(itemData)
  if entity == nil then
    log:error("Failed to create entity for item %s", name)
    return tostring(itemId)
  end

  -- Register binding if applicable
  entity:registerBinding()

  -- Register variable for variable types
  if MqttVariable.isVariableType(itemType) then
    entity:registerVariable()
  end

  log:info("Added item '%s' (type=%s, id=%s)", name, itemType, itemId)
  return tostring(itemId)
end

--- Delete an item
--- @param itemId string Item ID
local function deleteItem(itemId)
  log:trace("deleteItem(%s)", itemId)
  local items = getItems()
  local item = items[tostring(itemId)]

  if not item then
    log:warn("Item %s not found", itemId)
    return
  end

  local entity = getEntity(itemId)
  if entity then
    -- Unsubscribe from topics
    local deviceId = tostring(C4:GetDeviceID())
    entity:unsubscribe(deviceId)

    -- Unregister binding
    entity:unregisterBinding()

    -- Delete variable for variable types
    if MqttVariable.isVariableType(item.itemType) then
      entity:deleteVariable()
    end

    -- Delete state variable for relays, contacts, and events
    if item.itemType == "RELAY" or item.itemType == "CONTACT" or item.itemType == "EVENT" then
      values:delete(entity:getStateVarName())
    end

    -- Destroy entity
    destroyEntity(itemId)
  end

  -- Remove from storage
  items[tostring(itemId)] = nil
  saveItems(items)

  log:info("Deleted item '%s' (id=%s)", item.name, itemId)
end

--- Update item configuration
--- @param itemId string Item ID
--- @param config table Configuration updates
local function updateItemConfig(itemId, config)
  log:trace("updateItemConfig(%s, %s)", itemId, config)
  local items = getItems()
  local item = items[tostring(itemId)]

  if not item then
    log:warn("Item %s not found", itemId)
    return
  end

  local entity = getEntity(itemId)
  local deviceId = tostring(C4:GetDeviceID())

  -- Handle topic changes
  if config.stateTopic ~= nil and entity then
    local prevTopic = entity:getPreviousTopic()
    if prevTopic and prevTopic ~= config.stateTopic then
      log:debug("Unsubscribing from previous state topic: %s", prevTopic)
      SendToProxy(MQTT_BINDING, "UNSUBSCRIBE", { topic = prevTopic, device_id = deviceId })
    end
  end

  -- Update configuration
  for key, value in pairs(config) do
    item[key] = value
  end
  saveItems(items)

  -- Update entity's item reference
  if entity then
    entity.item = item

    -- Subscribe to new topic if needed
    if MqttDevice:isConnected() and config.stateTopic ~= nil then
      if not IsEmpty(item.stateTopic) then
        entity:subscribe(deviceId)
      end
    end
  end

  log:debug("Updated configuration for item '%s'", item.name)
end

-----------------------------------------------------------------------
-- Property management
-----------------------------------------------------------------------

--- Update the item properties (dynamic lists)
local function updateItemProperties()
  log:trace("updateItemProperties()")

  -- Clear add property fields
  UpdateProperty("Add Relay", "")
  UpdateProperty("Add Contact", "")
  UpdateProperty("Add Button", "")
  UpdateProperty("Add Event", "")
  UpdateProperty("Add String Variable", "")
  UpdateProperty("Add Bool Variable", "")
  UpdateProperty("Add Number Variable", "")
  UpdateProperty("Add Float Variable", "")
  UpdateProperty("Add Temperature Variable", "")
  UpdateProperty("Add Humidity Variable", "")

  -- Build item list
  local itemList = {}
  for _, item in pairs(getItems()) do
    table.insert(itemList, item.displayName)
  end
  table.sort(itemList)
  table.insert(itemList, 1, SELECT_OPTION)
  local itemOptions = table.concat(itemList, ",")

  -- Update dynamic lists
  C4:UpdatePropertyList("Remove Item", itemOptions, SELECT_OPTION)
  C4:UpdatePropertyList("Configure Item", itemOptions, SELECT_OPTION)

  -- Hide lists if only "(Select)" option available
  local visibility = #itemList <= 1 and constants.HIDE_PROPERTY or constants.SHOW_PROPERTY
  C4:SetPropertyAttribs("Remove Item", visibility)
  C4:SetPropertyAttribs("Configure Item", visibility)
  C4:SetPropertyAttribs("Manage Items", visibility)

  -- Trigger configure property handler to update visibility
  OnPropertyChanged("Configure Item")
end

--- @class VisibilityContext
--- @field hasItem boolean Whether an item is selected
--- @field isRelay boolean Whether selected item is a relay
--- @field isContact boolean Whether selected item is a contact
--- @field isButton boolean Whether selected item is a button
--- @field isEvent boolean Whether selected item is an event
--- @field isTemp boolean Whether selected item is a temperature sensor
--- @field isHumidity boolean Whether selected item is a humidity sensor
--- @field isSensor boolean Whether selected item is a sensor (temp or humidity)
--- @field hasStateTopic boolean Whether item has a state topic configured
--- @field hasCommandTopic boolean Whether item has a command topic configured
--- @field hasValuePath boolean Whether item has a value path configured

--- Visibility rules for item configuration properties.
--- @type table<string, fun(ctx: VisibilityContext): boolean>
local VISIBILITY_RULES = {
  ["Item Configuration"] = function(ctx)
    return ctx.hasItem
  end,
  ["State Topic"] = function(ctx)
    return ctx.hasItem and not ctx.isButton
  end,
  ["Command Topic"] = function(ctx)
    return ctx.hasItem and not ctx.isContact and not ctx.isSensor and not ctx.isEvent
  end,
  ["QoS"] = function(ctx)
    return ctx.hasStateTopic or ctx.hasCommandTopic
  end,
  ["Retain"] = function(ctx)
    return ctx.hasCommandTopic
  end,
  ["Payload On"] = function(ctx)
    return ctx.isRelay and ctx.hasCommandTopic
  end,
  ["Payload Off"] = function(ctx)
    return ctx.isRelay and ctx.hasCommandTopic
  end,
  ["State On"] = function(ctx)
    return ctx.isRelay and ctx.hasStateTopic
  end,
  ["State Off"] = function(ctx)
    return ctx.isRelay and ctx.hasStateTopic
  end,
  ["Optimistic"] = function(ctx)
    return ctx.isRelay
  end,
  ["State Open"] = function(ctx)
    return ctx.isContact and ctx.hasStateTopic
  end,
  ["State Closed"] = function(ctx)
    return ctx.isContact and ctx.hasStateTopic
  end,
  ["Payload Press"] = function(ctx)
    return ctx.isButton and ctx.hasCommandTopic
  end,
  ["Event Type Filter"] = function(ctx)
    return ctx.isEvent
  end,
  ["Temperature Scale"] = function(ctx)
    return ctx.isTemp
  end,
  ["State Topic Value"] = function(ctx)
    return ctx.hasStateTopic
  end,
  ["State"] = function(ctx)
    return (ctx.isRelay or ctx.isContact) and ctx.hasStateTopic
  end,
  ["Value Path"] = function(ctx)
    return ctx.hasStateTopic
  end,
  ["Value Path Result"] = function(ctx)
    return ctx.hasStateTopic and ctx.hasValuePath
  end,
}

--- Property value mappings for item configuration.
--- @type table<string, table|fun(item: table): string>
local PROPERTY_VALUES = {
  ["State Topic"] = { key = "stateTopic", default = "" },
  ["Command Topic"] = { key = "commandTopic", default = "" },
  ["Payload On"] = { key = "payloadOn", default = "" },
  ["Payload Off"] = { key = "payloadOff", default = "" },
  ["State On"] = { key = "stateOn", default = "" },
  ["State Off"] = { key = "stateOff", default = "" },
  ["Optimistic"] = { key = "optimistic", default = "Auto" },
  ["State Open"] = { key = "stateOpen", default = "" },
  ["State Closed"] = { key = "stateClosed", default = "" },
  ["Payload Press"] = { key = "payloadPress", default = "" },
  ["Event Type Filter"] = { key = "eventTypeFilter", default = "" },
  ["QoS"] = { key = "qos", default = "0" },
  ["Retain"] = function(item)
    return item.retain and "Yes" or "No"
  end,
  ["Temperature Scale"] = { key = "temperatureScale", default = "Celsius" },
  ["Value Path"] = { key = "valuePath", default = "" },
}

--- Update configuration property visibility based on selected item type.
local function updateItemConfigProperties()
  log:trace("updateItemConfigProperties()")
  local item = getSelectedItem() or {}
  local entity = getSelectedEntity()
  local hasItem = not IsEmpty(item)

  -- Build visibility context
  local isTemp = hasItem and item.itemType == "TEMPERATURE"
  local isHumidity = hasItem and item.itemType == "HUMIDITY"
  local ctx = {
    hasItem = hasItem,
    isRelay = hasItem and item.itemType == "RELAY",
    isContact = hasItem and item.itemType == "CONTACT",
    isButton = hasItem and item.itemType == "BUTTON",
    isEvent = hasItem and item.itemType == "EVENT",
    isTemp = isTemp,
    isHumidity = isHumidity,
    isSensor = isTemp or isHumidity,
    hasStateTopic = hasItem and not IsEmpty(item.stateTopic),
    hasCommandTopic = hasItem and not IsEmpty(item.commandTopic),
    hasValuePath = hasItem and not IsEmpty(item.valuePath),
  }

  -- Apply visibility rules
  for propName, predicate in pairs(VISIBILITY_RULES) do
    local visible = predicate(ctx)
    C4:SetPropertyAttribs(propName, visible and constants.SHOW_PROPERTY or constants.HIDE_PROPERTY)
  end

  -- Populate property values if item selected
  if not hasItem then
    return
  end

  -- Apply property value mappings
  for propName, mapping in pairs(PROPERTY_VALUES) do
    local value
    if type(mapping) == "function" then
      value = mapping(item)
    else
      value = item[mapping.key] or mapping.default
    end
    UpdateProperty(propName, value)
  end

  -- Populate read-only state properties from entity
  if entity then
    UpdateProperty("State Topic Value", entity:getTopicValue() or "")

    if ctx.hasValuePath then
      UpdateProperty("Value Path Result", entity:getValuePathResult() or "")
    end

    if ctx.isRelay or ctx.isContact then
      UpdateProperty("State", entity:getStateText())
    end
  end
end

--- Update availability property visibility
local function updateAvailabilityPropertyVisibility()
  log:trace("updateAvailabilityPropertyVisibility()")
  local hasAvailabilityTopic = not IsEmpty(Properties["Availability Topic"])
  local vis = hasAvailabilityTopic and constants.SHOW_PROPERTY or constants.HIDE_PROPERTY
  C4:SetPropertyAttribs("Availability Topic Value", vis)
  C4:SetPropertyAttribs("Availability Status", vis)
  C4:SetPropertyAttribs("Payload Available", vis)
  C4:SetPropertyAttribs("Payload Not Available", vis)
  C4:SetPropertyAttribs("Availability Value Path", vis)

  local hasAvailPath = not IsEmpty(Properties["Availability Value Path"])
  local pathResultVis = (hasAvailabilityTopic and hasAvailPath) and constants.SHOW_PROPERTY or constants.HIDE_PROPERTY
  C4:SetPropertyAttribs("Availability Value Path Result", pathResultVis)
end

--- Restore all items on driver init
local function restoreItems()
  log:trace("restoreItems()")

  -- First restore values from the values lib
  values:restoreValues()

  -- Create entity instances for all items
  for itemId, item in pairs(getItems()) do
    local entity = createEntity(item)
    if entity then
      -- Restore binding and handlers
      entity:registerBinding()

      -- Re-register variable callbacks
      if MqttVariable.isVariableType(item.itemType) then
        local currentValue = values:getValue(item.name)
        local value = currentValue and currentValue.value or ""
        entity:registerVariable(value)
      end

      -- Initialize topic tracking
      entity:recordTopic(item.stateTopic)
    end
  end

  -- Restore bindings
  bindings:restoreBindings()
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

  -- Initialize MqttDevice
  MqttDevice:init(MQTT_BINDING)
end

function OnDriverLateInit()
  log:trace("OnDriverLateInit()")
  if not CheckMinimumVersion("Driver Status") then
    return
  end
  UpdateProperty("Driver Status", "Initializing")

  -- Restore items and their callbacks/bindings
  restoreItems()

  -- Restore dynamic events from persistent storage
  events:restoreEvents()

  -- Fire OnPropertyChanged to set the initial Headers and other Property
  for p, _ in pairs(Properties) do
    local status, err = pcall(OnPropertyChanged, p)
    if not status and err ~= nil then
      log:error(err)
    end
  end
  gInitialized = true
  UpdateProperty("Driver Status", "Disconnected")

  -- Re-register availability events/conditional
  local hasAvailabilityTopic = not IsEmpty(Properties["Availability Topic"])
  MqttDevice:registerAvailabilityEvents(hasAvailabilityTopic)

  -- Update property visibility
  updateAvailabilityPropertyVisibility()
  updateItemProperties()

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

-- Availability property handlers
function OPC.Availability_Topic(propertyValue)
  log:trace("OPC.Availability_Topic('%s')", propertyValue)
  if not gInitialized then
    return
  end

  if IsEmpty(propertyValue) then
    MqttDevice:unregisterAvailabilityEvents()
  else
    MqttDevice:registerAvailabilityEvents(true)
  end

  local deviceId = tostring(C4:GetDeviceID())
  MqttDevice:subscribeToAvailability(propertyValue, deviceId)
  updateAvailabilityPropertyVisibility()
end

function OPC.Payload_Available(propertyValue)
  log:trace("OPC.Payload_Available('%s')", propertyValue)
  if not gInitialized then
    return
  end
  MqttDevice:reevaluateAvailability({
    valuePath = Properties["Availability Value Path"],
    payloadAvailable = propertyValue,
    payloadNotAvailable = Properties["Payload Not Available"],
  })
end

function OPC.Payload_Not_Available(propertyValue)
  log:trace("OPC.Payload_Not_Available('%s')", propertyValue)
  if not gInitialized then
    return
  end
  MqttDevice:reevaluateAvailability({
    valuePath = Properties["Availability Value Path"],
    payloadAvailable = Properties["Payload Available"],
    payloadNotAvailable = propertyValue,
  })
end

function OPC.Availability_Value_Path(propertyValue)
  log:trace("OPC.Availability_Value_Path('%s')", propertyValue)
  if not gInitialized then
    return
  end
  MqttDevice:reevaluateAvailability({
    valuePath = propertyValue,
    payloadAvailable = Properties["Payload Available"],
    payloadNotAvailable = Properties["Payload Not Available"],
  })
  updateAvailabilityPropertyVisibility()
end

--- Create an "Add Item" property handler.
--- @param itemType string The type of item to add.
--- @param propertyName string The add property name (for error display).
--- @return function handler The property change handler.
local function createAddItemHandler(itemType, propertyName)
  return function(propertyValue)
    log:trace("OPC.Add_%s('%s')", itemType, propertyValue)
    if not gInitialized then
      updateItemProperties()
      return
    end
    if IsEmpty(propertyValue) then
      return
    end

    local itemId = addItem(propertyValue, itemType)

    if itemId == nil then
      -- Show error in property field, then clear after delay
      UpdateProperty(propertyName, "Error: Item with name '" .. propertyValue .. "' already exists")
      delay(2 * ONE_SECOND):next(function()
        UpdateProperty(propertyName, "")
      end)
      return
    end

    updateItemProperties()

    local item = getItem(itemId)
    if item then
      UpdateProperty("Configure Item", item.displayName, true)
    end
  end
end

-- Add device handlers
OPC.Add_Relay = createAddItemHandler("RELAY", "Add Relay")
OPC.Add_Contact = createAddItemHandler("CONTACT", "Add Contact")
OPC.Add_Button = createAddItemHandler("BUTTON", "Add Button")
OPC.Add_Event = createAddItemHandler("EVENT", "Add Event")

-- Add variable handlers
OPC.Add_String_Variable = createAddItemHandler("STRING", "Add String Variable")
OPC.Add_Bool_Variable = createAddItemHandler("BOOL", "Add Bool Variable")
OPC.Add_Number_Variable = createAddItemHandler("NUMBER", "Add Number Variable")
OPC.Add_Float_Variable = createAddItemHandler("FLOAT", "Add Float Variable")
OPC.Add_Temperature_Variable = createAddItemHandler("TEMPERATURE", "Add Temperature Variable")
OPC.Add_Humidity_Variable = createAddItemHandler("HUMIDITY", "Add Humidity Variable")

-- Item management handlers
function OPC.Remove_Item(propertyValue)
  log:trace("OPC.Remove_Item('%s')", propertyValue)
  if not gInitialized then
    return
  end
  if propertyValue == SELECT_OPTION or IsEmpty(propertyValue) then
    return
  end

  local itemId = parseItemId(propertyValue)
  if itemId then
    deleteItem(itemId)
    updateItemProperties()
  end
end

function OPC.Configure_Item(propertyValue)
  log:trace("OPC.Configure_Item('%s')", propertyValue)
  updateItemConfigProperties()
end

--- Create an item config property handler.
--- @param configKey string The config key to update.
--- @param opts table|nil Optional settings.
--- @return function handler The property change handler.
local function createConfigHandler(configKey, opts)
  opts = opts or {}
  return function(propertyValue)
    log:trace("OPC.%s('%s')", configKey, propertyValue)
    local selectedItemId = getSelectedItemId()
    if not gInitialized or selectedItemId == nil then
      return
    end
    local value = propertyValue
    if opts.transform then
      value = opts.transform(propertyValue)
    elseif opts.default ~= nil then
      value = propertyValue or opts.default
    end
    updateItemConfig(selectedItemId, { [configKey] = value })
    if opts.postUpdate then
      opts.postUpdate(selectedItemId)
    end
  end
end

--- Re-evaluate state after config change.
--- @param itemId string Item ID.
local function reevaluateState(itemId)
  local entity = getEntity(itemId)
  if entity then
    local topicValue = entity:getTopicValue()
    if topicValue then
      entity:onMessage(topicValue)
    end
  end
  updateItemConfigProperties()
end

-- Item configuration handlers
OPC.Temperature_Scale = createConfigHandler("temperatureScale", { default = "Celsius" })
OPC.Value_Path = createConfigHandler("valuePath", { default = "", postUpdate = reevaluateState })
OPC.State_On = createConfigHandler("stateOn", { default = "", postUpdate = reevaluateState })
OPC.State_Off = createConfigHandler("stateOff", { default = "", postUpdate = reevaluateState })
OPC.State_Open = createConfigHandler("stateOpen", { default = "", postUpdate = reevaluateState })
OPC.State_Closed = createConfigHandler("stateClosed", { default = "", postUpdate = reevaluateState })
OPC.Command_Topic = createConfigHandler("commandTopic", { default = "", postUpdate = updateItemConfigProperties })
OPC.State_Topic = createConfigHandler("stateTopic", { default = "", postUpdate = updateItemConfigProperties })
OPC.Payload_On = createConfigHandler("payloadOn", { default = "" })
OPC.Payload_Off = createConfigHandler("payloadOff", { default = "" })
OPC.Payload_Press = createConfigHandler("payloadPress", { default = "" })
OPC.Event_Type_Filter = createConfigHandler("eventTypeFilter", { default = "" })
OPC.Optimistic = createConfigHandler("optimistic", { default = "Auto" })
OPC.QoS = createConfigHandler("qos", { default = "0" })
OPC.Retain = createConfigHandler("retain", {
  transform = function(v)
    return v == "Yes"
  end,
})

-----------------------------------------------------------------------
-- Receive From Proxy (RFP) handlers
-----------------------------------------------------------------------

function RFP.BROKER_CONNECTED(idBinding, strCommand, tParams, args)
  log:trace("RFP.BROKER_CONNECTED(%s, %s, %s, %s)", idBinding, strCommand, tParams, args)
  if idBinding ~= MQTT_BINDING then
    return
  end

  MqttDevice:setConnected(true)
  subscribeAllEntities()
end

function RFP.BROKER_DISCONNECTED(idBinding, strCommand, tParams, args)
  log:trace("RFP.BROKER_DISCONNECTED(%s, %s, %s, %s)", idBinding, strCommand, tParams, args)
  if idBinding ~= MQTT_BINDING then
    return
  end

  MqttDevice:setConnected(false)
end

-----------------------------------------------------------------------
-- On Binding Changed (OBC) handler
-----------------------------------------------------------------------

OBC[MQTT_BINDING] = function(idBinding, strClass, bIsBound, otherDeviceId, otherBindingId)
  log:trace("OBC[MQTT_BINDING](%s, %s, %s, %s, %s)", idBinding, strClass, bIsBound, otherDeviceId, otherBindingId)
  MqttDevice:reset()
  for _, entity in pairs(entities) do
    entity:reset()
  end
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

  -- Check global availability topic
  local availabilityTopic = Properties["Availability Topic"]
  if not IsEmpty(availabilityTopic) and topic == availabilityTopic then
    MqttDevice:updateAvailability(payload, {
      valuePath = Properties["Availability Value Path"],
      payloadAvailable = Properties["Payload Available"],
      payloadNotAvailable = Properties["Payload Not Available"],
    })
    return
  end

  -- Find entities that match this topic
  for itemId, entity in pairs(entities) do
    local item = getItem(itemId)
    if item and topic == item.stateTopic then
      log:info("Processing state for '%s': %s", item.name, payload)
      entity:onMessage(payload)

      -- Update properties if this is the selected item
      if getSelectedItemId() == itemId then
        updateItemConfigProperties()
      end
    end
  end
end

function getItemParamNames(itemType)
  log:trace("getItemParamNames(%s)", itemType)
  local names = {}
  for _, item in pairs(getItems()) do
    if itemType == nil or item.itemType == itemType then
      table.insert(names, item.name .. " [" .. item.id .. "]")
    end
  end
  table.sort(names)
  return names
end

function getItemByParamName(paramName)
  log:trace("getItemByParamName(%s)", paramName)
  for itemId, item in pairs(getItems()) do
    local itemParamName = item.name .. " [" .. item.id .. "]"
    if paramName == itemParamName then
      return item, getEntity(itemId)
    end
  end
  return nil, nil
end

function EC.Press(tParams)
  log:trace("EC.Press(%s)", tParams)

  local buttonParamName = Select(tParams, "Button")
  if IsEmpty(buttonParamName) then
    log:warn("Press command missing Button parameter")
    return
  end

  local item, entity = getItemByParamName(buttonParamName)
  if item and entity and entity.press then
    entity:press()
    return
  end

  log:warn("Button not found: %s", buttonParamName)
end

------------------------------------------------------------------------
-- Get Command Param List (GCPL) handlers for dynamic command parameters
------------------------------------------------------------------------

--- Get list of button names for Press command
function GCPL.Press(paramName)
  log:trace("GCPL.Press(%s)", paramName)
  if paramName ~= "Button" then
    return {}
  end
  return getItemParamNames("BUTTON")
end
