-- The DriverCentral build's license gate on the MQTT Broker, driven by the real vendored cloud client against a
-- fake Cloud driver (test/dc_cloud.lua) and a fake broker. Without a license the broker stays connected five
-- minutes after its load, then disconnects and refuses to connect; a license connects it again at once. A Cloud
-- driver update, a slow boot or a broker that drops while the Cloud driver is quiet leave a licensed broker up.
--
-- Run from the driver root:
--   make test
-- or:
--   ./test/run_test.sh test_license_gate.lua

require("c4_shim")
require("drivers-common-public.global.timer") -- CancelTimer, Timer and TimerFunctions, as driver.lua loads them
local T = require("testlib")
local F = require("c4_fixtures")
local cloud = require("dc_cloud")

local ROOT = (debug.getinfo(1, "S").source:match("@(.*[/\\])") or "./") .. "../"

function C4:GetVersionInfo()
  return { version = "4.3.0.763530-res" }
end
local configInfo = C4.GetDriverConfigInfo
function C4:GetDriverConfigInfo(section)
  if section == "version" then
    return "20261104"
  elseif section == "minimum_os_version" then
    return "3.3.0"
  end
  return configInfo(self, section)
end
function C4:UpdateProperty(name, value)
  Properties[name] = value
end
C4.FireEvent = function() end

-- The gate's own 10 s read, captured so a test runs it without firing every other timer.
local gateRead
local setTimer = C4.SetTimer
function C4:SetTimer(ms, fn, repeating)
  local handle = setTimer(self, ms, fn, repeating)
  if type(fn) == "function" and debug.getinfo(fn, "S").source:match("lib[/\\]drivercentral%.lua$") then
    gateRead = fn
  end
  return handle
end

-- A fake C4:MQTT client: Connect succeeds or fails as `broker.up` says, through its callbacks.
local broker
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
    self.connected = broker.up
    self.cb.OnConnect(self, broker.up and 0 or 5, 0, broker.up and "" or "not authorized")
  end
  function client:Disconnect()
    self.connected = false
  end
  function client:Subscribe() end
  function client:Unsubscribe() end
  function client:Publish(topic, payload)
    broker.published[#broker.published + 1] = topic .. "=" .. payload
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

local told
function C4:SendToProxy(_, command)
  told[#told + 1] = command
end

local function connected()
  return broker.client ~= nil and broker.client.connected == true
end

--- The broker drops the connection uncleanly.
local function brokerDrops()
  broker.client.connected = false
  broker.client.cb.OnDisconnect(broker.client, 7)
end

--- Fires the broker's 30 s reconnect timer, if one is armed.
local function reconnectTimer()
  local handle = Timer.reconnect
  if handle then
    TimerFunctions[handle](handle, 0)
  end
end

--- A load of the DriverCentral build with a fresh client and gate.
--- @param answer? table What the Cloud driver answers each ping with; nil answers nothing.
--- @param brokerUp? boolean Whether the broker host answers (true unless false).
local function load(answer, brokerUp)
  local gate = package.loaded["lib.drivercentral"]
  if type(gate) == "table" and gate._timer then
    gate._timer:Cancel()
  end
  package.loaded["lib.drivercentral"] = nil
  package.loaded["cloud-client-byte"] = nil
  CancelTimer("reconnect")
  cloud.ping, cloud.answer, cloud.silent, cloud.present = nil, answer, answer == nil, true
  broker = { up = brokerUp ~= false, published = {} }
  told = {}
  gateRead = nil
  DC_OnDriverStatus = nil
  Properties = {
    ["Broker Address"] = "192.0.2.20",
    ["Port"] = "1883",
    ["Username"] = "",
    ["Password"] = "",
    ["Keep Alive"] = "60",
    ["Log Level"] = "3 - Info",
    ["Log Mode"] = "Off",
    ["Cloud Status"] = "",
    ["Automatic Updates"] = "Off",
    ["Cloud Monitoring"] = "Disabled",
    ["Driver Status"] = "",
    ["Driver Version"] = "",
  }
  F.dofileBuild(ROOT .. "drivers/mqtt_broker/driver.lua", "drivercentral")
  OnDriverInit()
  ShimLateInit("DIT_STARTUP")
end

--- `n` rounds of 10 s: one ping, then one read by the gate.
--- @param n? integer
local function tick(n)
  for _ = 1, n or 1 do
    if cloud.ping then
      cloud.poll(1)
    end
    gateRead()
  end
end

T.section("A licensed broker or one in its trial stays connected")
do
  load({ AC = 1, AS = "License Activated" })
  tick(40)
  T.eq("licensed: connected after 400 s", connected(), true)
  T.eq("licensed: Driver Status", Properties["Driver Status"], "Connected")
  load({ AC = -720, AS = "Trial Running, 30 Days Remaining" })
  tick(40)
  T.eq("trial: connected", connected(), true)
end

T.section("Without a license the broker disconnects five minutes after its load and refuses to connect")
do
  load({ AC = 0, AS = "Invalid License" })
  T.eq("connected at its load, before the gate has read a 0 for long", connected(), true)
  tick(29)
  T.eq("29 reads of 0: still connected", connected(), true)
  told = {}
  tick()
  T.eq("the 30th read disconnects it", connected(), false)
  T.eq("Driver Status says why", Properties["Driver Status"], "No active license")
  T.eq("the companions are told", told[1], "BROKER_DISCONNECTED")
  ReceivedFromProxy(5001, "PUBLISH", { topic = "plug/set", payload = "ON" })
  T.eq("a companion's publish reaches no broker", #broker.published, 0)
  EC.Reconnect()
  T.eq("the Reconnect action is refused", connected(), false)
  OnPropertyChanged("Broker Address")
  T.eq("so is a settings change", connected(), false)
  tick(10)
  T.eq("and it stays disconnected", connected(), false)
end

T.section("A trial that expires disconnects the broker, and a purchase connects it at once")
do
  load({ AC = -1, AS = "Trial Running, 1 Hours Remaining" })
  cloud.answer = { AC = 0, AS = "Trial Expired" }
  tick(30)
  T.eq("disconnected 30 reads after the expiry", connected(), false)
  cloud.say({ AC = 1, AS = "License Activated" })
  T.eq("a license connects it without anyone pressing Reconnect", connected(), true)
  T.eq("Driver Status", Properties["Driver Status"], "Connected")
end

T.section("After a power cut the broker host comes up late and the Cloud driver answers late: it connects")
do
  load(nil, false)
  T.eq("the first connect fails", connected(), false)
  broker.up = true
  reconnectTimer()
  T.eq("the 30 s retry connects while the Cloud driver has not answered", connected(), true)
  tick(3)
  cloud.silent, cloud.answer = false, { AC = 1, AS = "License Activated" }
  tick(40)
  T.eq("and stays connected once it answers", connected(), true)
end

T.section("A broker that drops while the Cloud driver is quiet reconnects")
do
  load({ AC = 1, AS = "License Activated" })
  cloud.silent = true
  tick(6)
  T.eq("DC_X after a minute of Cloud driver silence", DC_X, 0)
  brokerDrops()
  reconnectTimer()
  T.eq("the retry connects", connected(), true)
  cloud.silent = false
  tick(40)
  T.eq("and it stays connected", connected(), true)
end

T.section("A Cloud driver update leaves a licensed broker connected")
do
  load({ AC = 1, AS = "License Activated" })
  cloud.say({ AC = 0, AS = "Cloud driver removed, please install cloud driver." })
  cloud.silent = true
  tick(3)
  cloud.silent = false
  tick(40)
  T.eq("connected throughout", connected(), true)
end

T.section(
  "A Cloud driver gone quiet disconnects the broker 30 reads after the client gives up, and an answer reconnects"
)
do
  load({ AC = 1, AS = "License Activated" })
  cloud.silent = true
  tick(34)
  T.eq("34 rounds of silence: connected", connected(), true)
  tick()
  T.eq("the 35th disconnects it", connected(), false)
  cloud.silent = false
  tick()
  T.eq("the first answer reconnects it", connected(), true)
end

T.section("MQTT Universal starts the client for the same product")
do
  package.loaded["cloud-client-byte"] = nil
  package.loaded["lib.drivercentral"] = nil
  Properties =
    { ["Cloud Status"] = "", ["Automatic Updates"] = "Off", ["Log Level"] = "3 - Info", ["Log Mode"] = "Off" }
  F.dofileBuild(ROOT .. "drivers/mqtt_universal/driver.lua", "drivercentral")
  OnDriverInit()
  T.eq("DC_PID", DC_PID, 857)
  T.eq("the client is loaded", package.loaded["cloud-client-byte"] ~= nil, true)
end

T.finish()
