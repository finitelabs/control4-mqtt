--- MQTT Universal Driver
--- A Control4 driver for integrating MQTT-based devices and variables.
---
--- This driver connects to an MQTT broker (via the MQTT Broker driver) and allows
--- dynamic creation of relays, contacts, buttons, and typed variables that communicate
--- over MQTT topics. Each item can be configured with state and command topics,
--- payload mappings, and JSONPath extraction for complex payloads.

require("lib.utils")
require("drivers-common-public.global.handlers")
require("drivers-common-public.global.lib")
require("drivers-common-public.global.timer")

JSON = require("JSON")

local bindings = require("lib.bindings")
local events = require("lib.events")
local log = require("lib.logging")
local persist = require("lib.persist")
--#ifdef DRIVERCENTRAL
local drivercentral = require("lib.drivercentral")
local updateSettings = require("lib.update-settings")
local supportCode = require("lib.support-code")
local diagnostics = require("lib.diagnostics")
--#endif
local values = require("lib.values")

-- MQTT entity modules
local mqttDevice = require("mqtt.entities.device")
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

--- Get all items from persistent storage.
--- @return table<string, table> items Items indexed by ID.
local function getItems()
  log:trace("getItems()")
  return persist:get(ITEMS_PERSIST_KEY, {}) or {}
end

--- Save items to persistent storage.
--- @param items table<string, table> Items to save.
local function saveItems(items)
  log:trace("saveItems(%s)", items)
  persist:set(ITEMS_PERSIST_KEY, not IsEmpty(items) and items or nil)
end

--- Get the next available item ID.
--- @return number itemId The next available ID.
local function getNextItemId()
  log:trace("getNextItemId()")
  local items = getItems()
  local id = 1
  while items[tostring(id)] do
    id = id + 1
  end
  return id
end

--- Get a single item by ID.
--- @param itemId string|number Item ID.
--- @return table|nil item Item data, or nil if not found.
local function getItem(itemId)
  log:trace("getItem(%s)", itemId)
  local items = getItems()
  return items[tostring(itemId)]
end

--- Parse item ID from display name format "Name (TYPE) [ID]".
--- @param displayName string Display name from dynamic list.
--- @return string|nil itemId The item ID, or nil.
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
--- @return table|nil item The selected item, or nil.
local function getSelectedItem()
  log:trace("getSelectedItem()")
  local itemId = getSelectedItemId()
  if itemId == nil then
    return nil
  end
  return getItem(itemId)
end

--- Get entity instance for an item.
--- @param itemId string|number Item ID.
--- @return MqttEntity|nil entity The entity instance, or nil.
local function getEntity(itemId)
  return entities[tostring(itemId)]
end

--- Get currently selected entity.
--- @return MqttEntity|nil entity The selected entity, or nil.
local function getSelectedEntity()
  local itemId = getSelectedItemId()
  if itemId == nil then
    return nil
  end
  return getEntity(itemId)
end

--- Create an entity instance for an item.
--- @param item table Item data.
--- @return MqttEntity|nil entity The entity instance, or nil for an unknown type.
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
  if not mqttDevice:isConnected() then
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
  mqttDevice:subscribeToAvailability(availabilityTopic, deviceId)
end

-----------------------------------------------------------------------
-- Item management
-----------------------------------------------------------------------

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

--- The key OnVariableChanged finds a variable's handler by: its name with each run of spaces as one underscore.
--- @param name string The variable name.
--- @return string key The handler key.
local function variableKey(name)
  return (string.gsub(name, "%s+", "_"))
end

--- The first variable a new item would own that is taken: by another item, by the driver's Availability Status,
--- or by a property, which a variable of the same name would overwrite.
--- @param name string The new item's name.
--- @param itemType string The new item's type.
--- @return string|nil variable The taken variable's name, or nil when all are free.
local function takenVariableName(name, itemType)
  local EntityClass = ENTITY_CLASSES[itemType]
  if EntityClass == nil then
    return nil
  end
  local taken = { [variableKey("Availability Status")] = true }
  for _, entity in pairs(entities) do
    for _, variable in ipairs(entity:getVariableNames()) do
      taken[variableKey(variable)] = true
    end
  end
  for _, variable in ipairs(EntityClass:new({ name = name, itemType = itemType }, MQTT_BINDING):getVariableNames()) do
    if taken[variableKey(variable)] or Properties[variable] ~= nil then
      return variable
    end
  end
  return nil
end

--- Add a new item.
--- @param name string Item name.
--- @param itemType string Item type.
--- @return string|nil itemId The new item's ID, or nil when its name or a variable it would own is taken.
--- @return string|nil reason Why the item was not added.
local function addItem(name, itemType)
  log:trace("addItem(%s, %s)", name, itemType)

  if itemNameExists(name) then
    log:print("Item with name '%s' already exists", name)
    return nil, "Item with name '" .. name .. "' already exists"
  end
  local takenVariable = takenVariableName(name, itemType)
  if takenVariable then
    log:print("Item '%s' not added; variable '%s' is already in use", name, takenVariable)
    return nil, "Variable '" .. takenVariable .. "' is already in use"
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

  local entity = createEntity(itemData)
  if entity == nil then
    log:error("Failed to create entity for item %s", name)
    return tostring(itemId)
  end

  entity:registerBinding()
  entity:seedVariables()
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
    local deviceId = tostring(C4:GetDeviceID())
    entity:unsubscribe(deviceId)

    entity:unregisterBinding()
    entity:deleteVariables()

    destroyEntity(itemId)
  end

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

  for key, value in pairs(config) do
    item[key] = value
  end
  saveItems(items)

  -- Update entity's item reference
  if entity then
    entity.item = item

    -- Subscribe to new topic if needed
    if mqttDevice:isConnected() and config.stateTopic ~= nil then
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

  local itemList = {}
  for _, item in pairs(getItems()) do
    table.insert(itemList, item.displayName)
  end
  table.sort(itemList)
  table.insert(itemList, 1, SELECT_OPTION)
  local itemOptions = table.concat(itemList, ",")

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

  for propName, predicate in pairs(VISIBILITY_RULES) do
    local visible = predicate(ctx)
    C4:SetPropertyAttribs(propName, visible and constants.SHOW_PROPERTY or constants.HIDE_PROPERTY)
  end

  -- Populate property values if item selected
  if not hasItem then
    return
  end

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

  for itemId, item in pairs(getItems()) do
    local entity = createEntity(item)
    if entity then
      entity:registerBinding()
      entity:seedVariables()
      if MqttVariable.isVariableType(item.itemType) then
        local currentValue = values:getValue(item.name)
        local value = currentValue and currentValue.value or ""
        entity:registerVariable(value)
      end

      -- Initialize topic tracking
      entity:recordTopic(item.stateTopic)
    end
  end
end

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

  mqttDevice:init(MQTT_BINDING)

  -- Restore values and bindings from persistent storage
  values:restoreValues()
  bindings:restoreBindings()
end

function OnDriverLateInit()
  log:trace("OnDriverLateInit()")
  if not CheckMinimumVersion("Driver Status") then
    return
  end
  UpdateProperty("Driver Status", "Initializing")

  events:restoreEvents()

  -- Restore items and their callbacks/bindings
  restoreItems()

  -- Fire OnPropertyChanged once per property to set initial globals.
  -- The router runs each handler in its own xpcall and reports its error, so the rest still run.
  for p, _ in pairs(Properties) do
    OnPropertyChanged(p)
  end
  gInitialized = true
  mqttDevice:refreshStatus()

  -- Re-register availability events/conditional
  local hasAvailabilityTopic = not IsEmpty(Properties["Availability Topic"])
  mqttDevice:registerAvailabilityEvents(hasAvailabilityTopic)

  updateAvailabilityPropertyVisibility()
  updateItemProperties()

  SendToProxy(MQTT_BINDING, "GET_STATUS", {}, "NOTIFY")
end

--#ifdef DRIVERCENTRAL
OnDriverLateInit = diagnostics:wrapLateInit(OnDriverLateInit)
--#endif

-----------------------------------------------------------------------
-- Property change handlers
-----------------------------------------------------------------------

--#ifdef DRIVERCENTRAL
function OPC.Automatic_Updates(propertyValue)
  log:trace("OPC.Automatic_Updates('%s')", propertyValue)
  if gInitialized then
    updateSettings:share("Automatic Updates", propertyValue)
  end
end
--#endif

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
end

-- Availability property handlers
function OPC.Availability_Topic(propertyValue)
  log:trace("OPC.Availability_Topic('%s')", propertyValue)
  if not gInitialized then
    return
  end

  mqttDevice:clearAvailability()
  if IsEmpty(propertyValue) then
    log:info("Availability Topic cleared; availability is no longer tracked")
  else
    mqttDevice:registerAvailabilityEvents(true)
  end

  local deviceId = tostring(C4:GetDeviceID())
  mqttDevice:subscribeToAvailability(propertyValue, deviceId)
  updateAvailabilityPropertyVisibility()
end

function OPC.Payload_Available(propertyValue)
  log:trace("OPC.Payload_Available('%s')", propertyValue)
  if not gInitialized then
    return
  end
  mqttDevice:reevaluateAvailability({
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
  mqttDevice:reevaluateAvailability({
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
  mqttDevice:reevaluateAvailability({
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

    local itemId, reason = addItem(propertyValue, itemType)

    if itemId == nil then
      -- Show error in property field, then clear after delay
      UpdateProperty(propertyName, "Error: " .. reason)
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

OPC.Add_Relay = createAddItemHandler("RELAY", "Add Relay")
OPC.Add_Contact = createAddItemHandler("CONTACT", "Add Contact")
OPC.Add_Button = createAddItemHandler("BUTTON", "Add Button")
OPC.Add_Event = createAddItemHandler("EVENT", "Add Event")

OPC.Add_String_Variable = createAddItemHandler("STRING", "Add String Variable")
OPC.Add_Bool_Variable = createAddItemHandler("BOOL", "Add Bool Variable")
OPC.Add_Number_Variable = createAddItemHandler("NUMBER", "Add Number Variable")
OPC.Add_Float_Variable = createAddItemHandler("FLOAT", "Add Float Variable")
OPC.Add_Temperature_Variable = createAddItemHandler("TEMPERATURE", "Add Temperature Variable")
OPC.Add_Humidity_Variable = createAddItemHandler("HUMIDITY", "Add Humidity Variable")

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
--- @param opts? table { default?: any, transform?: fun(v: string): any, postUpdate?: fun(itemId: string) }
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
      entity:onMessage(topicValue, true)
    end
  end
  updateItemConfigProperties()
end

--- Tell a sensor item's bound devices its reading again, in the scale just set.
--- @param itemId string Item ID.
local function resendReading(itemId)
  local entity = getEntity(itemId)
  if entity and entity.sendValue then
    entity:sendValue()
  end
end

OPC.Temperature_Scale = createConfigHandler("temperatureScale", { default = "Celsius", postUpdate = resendReading })
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

  mqttDevice:setConnected(true)
  subscribeAllEntities()
end

function RFP.BROKER_DISCONNECTED(idBinding, strCommand, tParams, args)
  log:trace("RFP.BROKER_DISCONNECTED(%s, %s, %s, %s)", idBinding, strCommand, tParams, args)
  if idBinding ~= MQTT_BINDING then
    return
  end

  mqttDevice:setConnected(false)
end

-----------------------------------------------------------------------
-- On Binding Changed (OBC) handler
-----------------------------------------------------------------------

OBC[MQTT_BINDING] = function(idBinding, strClass, bIsBound, otherDeviceId, otherBindingId)
  log:trace("OBC[MQTT_BINDING](%s, %s, %s, %s, %s)", idBinding, strClass, bIsBound, otherDeviceId, otherBindingId)
  mqttDevice:reset()
  for _, entity in pairs(entities) do
    entity:reset()
  end
  mqttDevice:refreshStatus()
  if bIsBound then
    SendToProxy(MQTT_BINDING, "GET_STATUS", {}, "NOTIFY")
  end
end

-----------------------------------------------------------------------
-- Execute Command (EC) handlers
-----------------------------------------------------------------------

--#ifdef DRIVERCENTRAL
--- An update setting changed on another item.
function EC.SET_UPDATE_SETTING(params)
  log:trace("EC.SET_UPDATE_SETTING(%s)", params)
  updateSettings:take(params)
end

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

function EC.MQTT_MESSAGE(tParams)
  log:trace("EC.MQTT_MESSAGE(%s)", tParams)

  local topic = Select(tParams, "topic")
  local payload = Select(tParams, "payload")
  local retained = toboolean(Select(tParams, "retain"))

  log:debug("Received MQTT message: topic=%s payload=%s retained=%s", topic, payload, retained)

  -- Check global availability topic
  local availabilityTopic = Properties["Availability Topic"]
  if not IsEmpty(availabilityTopic) and topic == availabilityTopic then
    mqttDevice:updateAvailability(payload, {
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
      entity:onMessage(payload, retained)

      -- Update properties if this is the selected item
      if getSelectedItemId() == itemId then
        updateItemConfigProperties()
      end
    end
  end
end

--- The items of a type as command parameters list them, "Name [ID]", sorted.
--- @param itemType string|nil The item type, or nil for every item.
--- @return string[] names The parameter names.
local function getItemParamNames(itemType)
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

--- Find an item by the "Name [ID]" a command parameter carries.
--- @param paramName string The parameter value.
--- @return table|nil item The item, or nil if none matches.
--- @return MqttEntity|nil entity The item's entity, or nil.
local function getItemByParamName(paramName)
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
