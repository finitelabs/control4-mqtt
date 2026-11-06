-- How the MQTT Broker's connection comes and goes: when Broker Connected and Broker Disconnected fire, what bound
-- items are told, and what BROKER_CONNECTED reads, by driving the open-source build with a fake MQTT client.
--
-- Run from the driver root:
--   make test
-- or:
--   ./test/run_test.sh test_broker_connection.lua
--
-- The fake client answers Connect and Disconnect later, as the real one does, and a broker that refuses a connection
-- closes it after its refusal.

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
function C4:UpdateProperty(name, value)
  Properties[name] = value
end

local broker = { up = true }
local queued = {}
function C4:MQTT()
  local client = { cb = {} }
  for _, name in ipairs({ "OnConnect", "OnDisconnect", "OnMessage", "OnPublish", "OnSubscribe" }) do
    client[name] = function(self, fn)
      self.cb[name] = fn
    end
  end
  function client:SetUsernameAndPassword() end
  function client:Connect()
    broker.client = self
    local up = broker.up
    queued[#queued + 1] = function()
      self.cb.OnConnect(self, up and 0 or 5, 0, up and "" or "not authorized")
      if not up then
        self.cb.OnDisconnect(self, 5, "")
      end
    end
  end
  function client:Disconnect()
    queued[#queued + 1] = function()
      self.cb.OnDisconnect(self, 0, "")
    end
  end
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

local fired, told = {}, {}
C4.FireEvent = function(_, name)
  fired[#fired + 1] = name
end
C4.SendToProxy = function(_, _binding, command)
  told[#told + 1] = command
end

--- Lets the client make the callbacks it has queued.
local function answer()
  while #queued > 0 do
    table.remove(queued, 1)()
  end
end

--- Runs the armed reconnect, if any, and lets the client answer. Returns whether one was armed.
local function retry()
  local handle = Timer.reconnect
  if not handle then
    return false
  end
  TimerFunctions[handle](handle, 0)
  answer()
  return true
end

--- The broker drops the session uncleanly.
local function drop()
  broker.client.cb.OnDisconnect(broker.client, 7, "connection lost")
end

--- What BROKER_CONNECTED says.
local function reads()
  return TC.BROKER_CONNECTED("BROKER_CONNECTED", { VALUE = "Connected", LOGIC = "EQUAL" }) and "Connected"
    or "Disconnected"
end

--- Clears what has fired and been told.
local function reset()
  fired, told = {}, {}
end

Properties = {
  ["Broker Address"] = "192.0.2.20",
  ["Port"] = "1883",
  ["Username"] = "",
  ["Password"] = "",
  ["Keep Alive"] = "60",
  ["Log Level"] = "3 - Info",
  ["Log Mode"] = "Off",
  ["Automatic Updates"] = "Off",
  ["Update Channel"] = "Production",
  ["Driver Status"] = "",
  ["Driver Version"] = "",
}
F.dofileBuild(ROOT .. "drivers/mqtt_broker/driver.lua", "oss")
OnDriverInit()
OnDriverLateInit("DIT_STARTUP")
answer()

--------------------------------------------------------------------------------
T.section("a start that connects fires Broker Connected")
--------------------------------------------------------------------------------

T.eq("Broker Connected once", fired, { "Broker Connected" })
-- Bound items hear the broker is down first: after a driver update they may still think it is up.
T.eq("bound items hear it is down, then up", told, { "BROKER_DISCONNECTED", "BROKER_CONNECTED" })
T.eq("BROKER_CONNECTED reads Connected", reads(), "Connected")

--------------------------------------------------------------------------------
T.section("Reconnect on a live session fires Broker Disconnected, then Broker Connected")
--------------------------------------------------------------------------------

reset()
EC.Reconnect()
T.eq("Broker Disconnected as the session goes down", fired, { "Broker Disconnected" })
answer()
T.eq("then Broker Connected", fired, { "Broker Disconnected", "Broker Connected" })
T.eq("bound items hear the same", told, { "BROKER_DISCONNECTED", "BROKER_CONNECTED" })

--------------------------------------------------------------------------------
T.section("a change to a broker that refuses fires Broker Disconnected once, and its retries fire nothing")
--------------------------------------------------------------------------------

reset()
broker.up = false
Properties["Broker Address"] = "192.0.2.21"
OnPropertyChanged("Broker Address")
answer()
T.eq("Broker Disconnected once", fired, { "Broker Disconnected" })
T.eq("bound items are told once", told, { "BROKER_DISCONNECTED" })
T.eq("BROKER_CONNECTED reads Disconnected", reads(), "Disconnected")
for i = 1, 3 do
  T.truthy("retry " .. i .. " is armed", retry())
end
T.eq("the refused retries fire nothing more", fired, { "Broker Disconnected" })
T.eq("and tell nothing more", told, { "BROKER_DISCONNECTED" })

broker.up = true
T.truthy("a last retry is armed", retry())
T.eq("the retry that connects fires Broker Connected", fired, { "Broker Disconnected", "Broker Connected" })

--------------------------------------------------------------------------------
T.section("a dropped session fires Broker Disconnected once until it is back")
--------------------------------------------------------------------------------

reset()
broker.up = false
drop()
T.eq("Broker Disconnected", fired, { "Broker Disconnected" })
T.eq("BROKER_CONNECTED reads Disconnected", reads(), "Disconnected")
for i = 1, 3 do
  T.truthy("retry " .. i .. " is armed", retry())
end
T.eq("the refused retries fire nothing more", fired, { "Broker Disconnected" })
broker.up = true
retry()
T.eq("Broker Connected once it is back", fired, { "Broker Disconnected", "Broker Connected" })
T.eq("bound items hear each change once", told, { "BROKER_DISCONNECTED", "BROKER_CONNECTED" })
T.eq("BROKER_CONNECTED reads Connected", reads(), "Connected")

T.finish()
