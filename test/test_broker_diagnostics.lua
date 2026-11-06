-- What Cloud Monitoring hears from the MQTT Broker's DriverCentral build: an error in a callback the MQTT client
-- runs, or in a property handler during the late init, is reported, and the callback's error goes no further.
--
-- Run from the driver root:
--   make test
-- or:
--   ./test/run_test.sh test_broker_diagnostics.lua

require("c4_shim")
require("drivers-common-public.global.timer")
local T = require("testlib")
local F = require("c4_fixtures")

local ROOT = (debug.getinfo(1, "S").source:match("@(.*[/\\])") or "./") .. "../"

function C4:GetVersionInfo()
  return { version = "4.3.0.763530-res" }
end
local configInfo = C4.GetDriverConfigInfo
function C4:GetDriverConfigInfo(section)
  if section == "version" then
    return "20261106"
  elseif section == "minimum_os_version" then
    return "3.3.0"
  end
  return configInfo(self, section)
end

-- Only the reports matter here, so the licensing client stays out.
package.loaded["cloud-client-byte"] = true

local client
function C4:MQTT()
  client = { cb = {} }
  for _, name in ipairs({ "OnConnect", "OnDisconnect", "OnMessage", "OnPublish", "OnSubscribe" }) do
    client[name] = function(self, fn)
      self.cb[name] = fn
    end
  end
  function client:SetUsernameAndPassword() end
  function client:Connect()
    self.cb.OnConnect(self, 0, 0, "")
  end
  function client:Disconnect() end
  function client:Subscribe() end
  function client:Unsubscribe() end
  function client:Publish()
    return 0
  end
  function client:ReasonCodeToString(code)
    return "reason " .. tostring(code)
  end
  function client:ErrorCodeToString(code)
    return "error " .. tostring(code)
  end
  return client
end

local failDelivery = false
function C4:UpdateProperty(name, value)
  Properties[name] = value
end
function C4:SendToDevice()
  if failDelivery then
    error("delivery failed")
  end
end
C4.SendToProxy = function() end
C4.FireEvent = function() end

Properties = {
  ["Broker Address"] = "192.0.2.20",
  ["Port"] = "1883",
  ["Username"] = "",
  ["Password"] = "",
  ["Keep Alive"] = "60",
  ["Log Level"] = "3 - Info",
  ["Log Mode"] = "Off",
  ["Automatic Updates"] = "Off",
  ["Cloud Monitoring"] = "Disabled",
  ["Cloud Status"] = "",
  ["Driver Status"] = "",
  ["Driver Version"] = "",
}
F.dofileBuild(ROOT .. "drivers/mqtt_broker/driver.lua", "drivercentral")

-- The property dispatcher catches a handler's own error, so this one is raised in the dispatcher.
local failDispatch = true
local handlerDebug = HandlerDebug
function HandlerDebug(init, ...)
  if failDispatch and init[1] == "OnPropertyChanged: Driver_Version" then
    error("dispatch failed")
  end
  return handlerDebug(init, ...)
end

local reported = {}
local diagnostics = require("lib.diagnostics")
function diagnostics:captureError(message, _traceback, source)
  reported[#reported + 1] = { source = source, message = message }
end

OnDriverInit()
OnDriverLateInit("DIT_STARTUP")
failDispatch = false

--- The sources reported since `from`.
local function sourcesSince(from)
  local sources = {}
  for i = from + 1, #reported do
    sources[#sources + 1] = reported[i].source
  end
  return sources
end

--------------------------------------------------------------------------------
T.section("an error the property replay catches during the late init is reported")
--------------------------------------------------------------------------------

T.eq("one report, from the property replay", sourcesSince(0), { "MQTTBroker.OnPropertyChanged" })
T.truthy("with the error", reported[1] and reported[1].message:find("dispatch failed", 1, true) ~= nil)
T.eq("and the broker still connects", Properties["Driver Status"], "Connected")

--------------------------------------------------------------------------------
T.section("an error in a client callback is reported and goes no further")
--------------------------------------------------------------------------------

for _, name in ipairs({ "OnConnect", "OnDisconnect", "OnMessage", "OnPublish", "OnSubscribe" }) do
  local source = debug.getinfo(client.cb[name], "S").source
  T.truthy(name .. " runs through Cloud Monitoring's wrap", source:match("lib[/\\]diagnostics%.lua$") ~= nil)
end

RFP.SUBSCRIBE(5001, "SUBSCRIBE", { topic = "door/state", device_id = "900", qos = "0" })
local before = #reported
failDelivery = true
local ok = pcall(client.cb.OnMessage, client, 1, "door/state", "ON", 0, false)
failDelivery = false
T.truthy("a failed delivery doesn't escape the callback", ok)
T.eq("it is reported as the message callback's", sourcesSince(before), { "MQTTBroker.OnMessage" })

T.finish()
