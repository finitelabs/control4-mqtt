-- What the MQTT Broker sends a child that subscribes to a topic it already follows, by driving the open-source
-- build with a fake MQTT client and reading what reaches C4:SendToDevice.
--
-- Run from the driver root:
--   make test
-- or:
--   ./test/run_test.sh test_broker_replay.lua
--
-- A reloaded MQTT Universal subscribes again to topics the Broker already follows, and the server sends nothing
-- for those, so the Broker replays the last message it kept. That replay is marked retained, as a server marks
-- what it sends because of a new subscription, so a child can tell it from a message just published.

require("c4_shim")
require("drivers-common-public.global.timer")
local T = require("testlib")

local ROOT = (debug.getinfo(1, "S").source:match("@(.*[/\\])") or "./") .. "../"
local CHILD = 900

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

--- Runs `path` as the open-source build compiles it: the DriverCentral lines are blanked.
--- @param path string
local function dofileOpenSource(path)
  local f = assert(io.open(path))
  local lines, stack, including = {}, {}, true
  for line in f:lines() do
    local ifdef, name = line:match("^%s*%-%-%s*#(ifn?def)%s+([%w_]+)%s*$")
    if ifdef then
      stack[#stack + 1] = including
      including = including and (name == "DRIVERCENTRAL") == (ifdef == "ifndef")
    elseif line:match("^%s*%-%-%s*#else%s*$") then
      including = stack[#stack] and not including
    elseif line:match("^%s*%-%-%s*#endif%s*$") then
      including = table.remove(stack)
    end
    lines[#lines + 1] = including and line or ""
  end
  f:close()
  return assert(load(table.concat(lines, "\n"), "@" .. path))()
end

local client
function C4:MQTT()
  client = { cb = {}, subscribed = {} }
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
  function client:Subscribe(topic)
    self.subscribed[#self.subscribed + 1] = topic
  end
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

local delivered = {}
function C4:SendToDevice(deviceId, command, params)
  if command == "MQTT_MESSAGE" then
    delivered[#delivered + 1] =
      { deviceId = deviceId, topic = params.topic, payload = params.payload, retain = params.retain }
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
  ["Update Channel"] = "Production",
  ["Driver Status"] = "",
  ["Driver Version"] = "",
}
dofileOpenSource(ROOT .. "drivers/mqtt_broker/driver.lua")
OnDriverInit()
OnDriverLateInit("DIT_STARTUP")

local function subscribe(topic)
  RFP.SUBSCRIBE(5001, "SUBSCRIBE", { topic = topic, device_id = tostring(CHILD), qos = "0" })
end

--------------------------------------------------------------------------------
T.section("a message just published is passed on as it came")
--------------------------------------------------------------------------------

subscribe("door/event")
T.eq("the first subscription reaches the server", client.subscribed, { "door/event" })
client.cb.OnMessage(client, 1, "door/event", "press", 0, false)
T.eq("one message reaches the child", #delivered, 1)
T.eq("not marked retained", delivered[1] and delivered[1].retain, "false")

delivered = {}
client.cb.OnMessage(client, 2, "door/state", "ON", 0, true)
subscribe("door/state")
client.cb.OnMessage(client, 3, "door/state", "ON", 0, true)
T.eq("a server's retained delivery stays marked retained", delivered[1] and delivered[1].retain, "true")

--------------------------------------------------------------------------------
T.section("a subscription to a followed topic gets the kept message, marked retained")
--------------------------------------------------------------------------------

delivered = {}
subscribe("door/event")
T.eq("no second subscription to the server", client.subscribed, { "door/event", "door/state" })
T.eq("the kept message reaches the child", #delivered, 1)
T.eq("with its payload", delivered[1] and delivered[1].payload, "press")
T.eq("marked retained, though it was published live", delivered[1] and delivered[1].retain, "true")

T.finish()
