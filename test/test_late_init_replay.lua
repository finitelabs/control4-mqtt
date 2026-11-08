-- Each driver's late init replays every property through OnPropertyChanged with no pcall of its own. The router
-- runs each handler in an xpcall and keeps its error, so a handler that raises stops neither the replay nor the
-- late init. Each driver loads in a Lua of its own: this file runs again with the driver's name.
--
-- Run from the driver root:
--   make test
-- or:
--   ./test/run_test.sh test_late_init_replay.lua

local T = require("testlib")

local HERE = debug.getinfo(1, "S").source:match("@(.*[/\\])") or "./"
local ROOT = HERE .. "../"
local PROBE = "Late Init Probe"
local PROBE_ERROR = "the probe's handler failed"

local function readFile(path)
  local f = assert(io.open(path, "r"))
  local text = f:read("*a")
  f:close()
  return text
end

--- Load one driver with its driver.xml defaults and a property whose handler raises, run its late init, and write
--- what happened as "@@ key value" lines.
--- @param name string The driver's directory under drivers/.
local function replay(name)
  local dir = ROOT .. "drivers/" .. name .. "/"
  package.preload["cloud-client-byte"] = function()
    return {}
  end
  local configInfo = C4.GetDriverConfigInfo
  function C4:GetDriverConfigInfo(section)
    return section == "minimum_os_version" and "3.3.0" or configInfo(self, section)
  end
  function C4:GetVersionInfo()
    return { version = "4.3.0" }
  end
  for block in readFile(dir .. "driver.xml"):gmatch("<property>(.-)</property>") do
    local property = block:match("<name>(.-)</name>")
    if property then
      Properties[property] = block:match("<default>(.-)</default>") or ""
    end
  end
  -- What leaves the late init: an error it raises, or one the diagnostics wrapper catches and reports.
  local escaped = ""
  local diagnostics = require("lib.diagnostics")
  function diagnostics:captureError(message, _, source)
    if source == "OnDriverLateInit" then
      escaped = escaped .. tostring(message)
    end
  end

  local loaded, loadErr = T.capture(function()
    dofile(dir .. "driver.lua")
    OnDriverInit()
  end)
  Properties[PROBE] = "x"
  OPC.Late_Init_Probe = function()
    error(PROBE_ERROR)
  end
  local router, replayed = OnPropertyChanged, {}
  OnPropertyChanged = function(property)
    replayed[property] = true
    return router(property)
  end
  local _, lateErr, out = T.capture(function()
    OnDriverLateInit()
  end)
  escaped = escaped .. tostring(lateErr or "")

  local missed = {}
  for property in pairs(Properties) do
    if not replayed[property] then
      missed[#missed + 1] = property
    end
  end
  table.sort(missed)
  io.write("@@ loaded ", loaded and "yes" or tostring(loadErr):gsub("\n", " "), "\n")
  io.write("@@ escaped ", tostring(escaped:find(PROBE_ERROR, 1, true) ~= nil), "\n")
  io.write("@@ missed ", table.concat(missed, ", "), "\n")
  io.write("@@ probe ", tostring(replayed[PROBE] == true), "\n")
  io.write("@@ printed ", tostring(out:find("OnPropertyChanged error", 1, true) ~= nil), "\n")
end

if arg[1] then
  replay(arg[1])
  return
end

local names = {}
local list = assert(io.popen(string.format("ls %q", ROOT .. "drivers")))
for name in list:lines() do
  local f = io.open(ROOT .. "drivers/" .. name .. "/driver.lua", "r")
  if f then
    f:close()
    names[#names + 1] = name
  end
end
list:close()
T.check("there are drivers to load", #names > 0)

for _, name in ipairs(names) do
  T.section(name .. "'s late init replays every property past a handler that raises")
  local run = assert(io.popen(string.format("luajit -e \"require('c4_shim')\" %q %q 2>&1", arg[0], name)))
  local out = run:read("*a")
  run:close()
  local got = {}
  for key, value in out:gmatch("@@ (%S+) ([^\n]*)") do
    got[key] = value
  end
  T.eq("the driver loads", got.loaded, "yes")
  T.eq("the handler's error doesn't leave the late init", got.escaped, "false")
  T.eq("every property is replayed", got.missed, "")
  T.eq("the one whose handler raised too", got.probe, "true")
  T.eq("and the router prints that handler's error", got.printed, "true")
  if not got.loaded then
    print(out)
  end
end

T.finish()
