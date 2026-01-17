--- MQTT Button entity.
--- Handles button press commands. Buttons are command-only (no state tracking).
--- Provides a BUTTON_LINK binding that can be connected to keypads and other controllers.
--- @class MqttButton:MqttEntity

local log = require("lib.logging")
local bindings = require("lib.bindings")
local MqttEntity = require("mqtt.entities.base")

local MqttButton = setmetatable({
  TYPE = "BUTTON",
  BINDING_CLASS = "BUTTON_LINK",
  BINDING_TYPE = "CONTROL",
  BINDINGS_NAMESPACE = "MqttButton",
}, { __index = MqttEntity })

--- Create a new button entity instance.
--- @param item table The item configuration.
--- @param brokerBinding number The broker binding ID.
--- @return MqttButton
function MqttButton:new(item, brokerBinding)
  local instance = MqttEntity.new(self, item, brokerBinding)
  setmetatable(instance, self)
  self.__index = self
  return instance
end

--- Get the binding key for this button.
--- @return string
function MqttButton:getBindingKey()
  return "button_" .. self:getId()
end

--- Press the button (publish command).
function MqttButton:press()
  if IsEmpty(self.item.commandTopic) then
    log:warn("Cannot press button '%s' - no command topic configured", self:getName())
    return
  end

  local payload = self.item.payloadPress or "PRESS"

  log:info("Pressing button '%s': %s -> %s", self:getName(), self.item.commandTopic, payload)
  self:publish(self.item.commandTopic, payload)
end

--- Register the BUTTON_LINK binding and RFP handler.
--- @return table|nil binding The created binding or nil on failure.
function MqttButton:registerBinding()
  local binding = bindings:getOrAddDynamicBinding(
    self.BINDINGS_NAMESPACE,
    self:getBindingKey(),
    self.BINDING_TYPE,
    true, -- provider
    self:getName(),
    self.BINDING_CLASS
  )

  if binding == nil then
    log:error("Failed to create BUTTON_LINK binding for button '%s'", self:getName())
    return nil
  end

  log:info("Registered BUTTON_LINK binding for '%s' (bindingId=%s)", self:getName(), binding.bindingId)

  -- Register RFP handler for DO_CLICK from keypads/controllers
  local entity = self
  RFP[binding.bindingId] = function(idBinding, strCommand, tParams, _args)
    log:debug("RFP[%s] strCommand=%s tParams=%s", idBinding, strCommand, tParams)

    if strCommand == "DO_CLICK" then
      entity:press()
    else
      log:debug("Unhandled command from BUTTON_LINK binding %s: %s", idBinding, strCommand)
    end
  end

  return binding
end

--- Unregister the button binding.
function MqttButton:unregisterBinding()
  local binding = bindings:getDynamicBinding(self.BINDINGS_NAMESPACE, self:getBindingKey())
  if binding then
    RFP[binding.bindingId] = nil
  end
  bindings:deleteBinding(self.BINDINGS_NAMESPACE, self:getBindingKey())
  log:debug("Unregistered BUTTON_LINK binding for button '%s'", self:getName())
end

return MqttButton
