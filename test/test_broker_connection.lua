-- How the MQTT Broker's connection comes and goes: when Broker Connected and Broker Disconnected fire, what bound
-- items are told, and what BROKER_CONNECTED reads, by driving the open-source build with a fake MQTT client.
--
-- Run from the driver root:
--   make test
-- or:
--   ./test/run_test.sh test_broker_connection.lua
--
-- The fake client answers Connect and Disconnect later, as the real one does. A broker that refuses a connection
-- closes it after its refusal, one that never answers just closes it, and a host name that doesn't resolve fails
-- Connect itself with no callback.

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

local broker = { up = true, answers = true }
-- What Connect returns when the host name doesn't resolve; nil when it does.
local lookupError
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
    if lookupError then
      return unpack(lookupError)
    end
    local up, answers, down = broker.up, broker.answers, broker.down
    queued[#queued + 1] = function()
      if down then
        -- What the controller's client calls back for a broker that is down (measured on 4.3).
        self.cb.OnDisconnect(self, 0, "Success")
        self.cb.OnDisconnect(self, 4, "Disconnect with Will Message")
        return
      end
      if not answers then
        self.cb.OnDisconnect(self, 14, "connection refused")
        return
      end
      self.cb.OnConnect(self, up and 0 or 5, 0, up and "" or "not authorized")
      if not up then
        self.cb.OnDisconnect(self, 5, "")
      end
    end
  end
  function client:Disconnect()
    self.disconnected = true
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

local now = 1000000
os.time = function()
  return now
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
--- @param message? string
local function drop(message)
  broker.client.cb.OnDisconnect(broker.client, 7, message or "connection lost")
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

local waits = {}
local setTimer = SetTimer
function SetTimer(id, delay, ...)
  if id == "reconnect" then
    waits[#waits + 1] = delay
  end
  return setTimer(id, delay, ...)
end
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

--------------------------------------------------------------------------------
T.section("Driver Status says why a session dropped, and that it is retrying")
--------------------------------------------------------------------------------

drop()
T.eq("with the client's message", Properties["Driver Status"], "Disconnected: connection lost (retrying)")
T.truthy("a retry is armed", retry())
drop("")
T.eq("or the reason code's meaning", Properties["Driver Status"], "Disconnected: reason 7 (retrying)")
retry()

broker.client.cb.OnDisconnect(broker.client, 0, "")
T.eq("a server's clean close is a plain Disconnected", Properties["Driver Status"], "Disconnected")
T.falsy("and is not retried", retry())

--------------------------------------------------------------------------------
T.section("a failed connect says why, and keeps saying it after the broker closes the connection")
--------------------------------------------------------------------------------

broker.up = false
EC.Reconnect()
answer()
T.eq("a refusal keeps its reason", Properties["Driver Status"], "Connect failed: not authorized")
T.truthy("and is retried", retry())

broker.up, broker.answers = true, false
retry()
T.eq("an attempt the broker never answers says why", Properties["Driver Status"], "Connect failed: connection refused")
broker.answers = true
T.truthy("and is retried", retry())
T.eq("until it connects", Properties["Driver Status"], "Connected")

--------------------------------------------------------------------------------
T.section("a broker host name that doesn't resolve says why and is retried")
--------------------------------------------------------------------------------

lookupError = { 15, "Lookup error" }
Properties["Broker Address"] = "broker.invalid"
OnPropertyChanged("Broker Address")
answer()
T.eq("with the client's description", Properties["Driver Status"], "Connect failed: Lookup error")
T.truthy("a retry is armed", retry())
lookupError = { 15 }
retry()
T.eq("or the error code's meaning", Properties["Driver Status"], "Connect failed: error 15")
lookupError = nil
T.truthy("and it connects once the name resolves", retry())
T.eq("Driver Status", Properties["Driver Status"], "Connected")

--------------------------------------------------------------------------------
T.section("retries wait longer each time, and a session that lasted starts them over")
--------------------------------------------------------------------------------

waits = {}
broker.up = false
now = now + 600
drop()
for _ = 1, 5 do
  retry()
end
T.eq("the waits double from 2 s to 30 s", waits, { 2000, 4000, 8000, 16000, 30000, 30000 })

broker.up = true
retry()
waits = {}
now = now + 600
drop()
T.eq("after a session that lasted, the first wait is 2 s", waits, { 2000 })
retry()

waits = {}
for _ = 1, 2 do
  now = now + 5
  drop()
  retry()
end
T.eq("sessions that end at once keep the waits growing", waits, { 4000, 8000 })

broker.up = false
for _ = 1, 4 do
  retry()
end
broker.up = true
retry()
T.eq("the waits are back at the cap", Properties["Driver Status"], "Connected")
waits = {}
now = now + 600
broker.up = false
EC.Reconnect()
answer()
T.eq("a Reconnect after a session that lasted starts the waits over", waits, { 2000 })
broker.up = true
retry()

--------------------------------------------------------------------------------
T.section("a refusal with no message says the reason code's meaning")
--------------------------------------------------------------------------------

broker.client.cb.OnConnect(broker.client, 5, 0, "")
T.eq("rather than nothing", Properties["Driver Status"], "Connect failed: reason 5")
retry()

--------------------------------------------------------------------------------
T.section("a broker that is down is retried until it is back")
--------------------------------------------------------------------------------

waits = {}
reset()
now = now + 600
broker.down = true
drop("The connection was lost.")
T.eq("the drop fires Broker Disconnected", fired, { "Broker Disconnected" })
retry()
T.eq("a failed attempt reads Connect failed", Properties["Driver Status"], "Connect failed")
T.truthy("and is retried", retry())
T.truthy("and again", retry())
T.eq("with the waits growing", waits, { 2000, 4000, 8000, 16000 })
T.eq("and no more Broker Disconnected", fired, { "Broker Disconnected" })
broker.down = false
T.truthy("the next retry", retry())
T.eq("connects", Properties["Driver Status"], "Connected")
T.eq("and fires Broker Connected once", fired, { "Broker Disconnected", "Broker Connected" })

--------------------------------------------------------------------------------
T.section("Reconnect is a programming command as well as an action")
--------------------------------------------------------------------------------

local xmlFile = assert(io.open(ROOT .. "drivers/mqtt_broker/driver.xml"))
local commands = xmlFile:read("*a"):match("<commands>(.-)</commands>") or ""
xmlFile:close()
T.truthy("driver.xml declares the command", commands:find("<name>Reconnect</name>", 1, true) ~= nil)
reset()
ExecuteCommand("Reconnect", {})
answer()
T.eq("and running it reconnects", fired, { "Broker Disconnected", "Broker Connected" })

--------------------------------------------------------------------------------
T.section("removing or updating the broker closes its connection and leaves nothing armed")
--------------------------------------------------------------------------------

reset()
local live = broker.client
OnDriverDestroyed()
T.truthy("the live session is disconnected", live.disconnected)
answer()
T.eq("its disconnect fires nothing", fired, {})
T.falsy("and arms no retry", retry())
T.eq("the update check is cancelled", Timer.UpdateCheck, nil)

broker.up = false
EC.Reconnect()
answer()
T.truthy("a refused attempt arms a retry", Timer.reconnect ~= nil)
OnDriverDestroyed()
T.eq("which is cancelled", Timer.reconnect, nil)

T.finish()
