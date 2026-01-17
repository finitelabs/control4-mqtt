--- @module "lib.state_parser"
--- Generic state parsing utilities using "match one, default other" logic.
---
--- This module extracts the common pattern used for parsing boolean states from
--- MQTT payloads throughout the mqtt_universal driver. The logic handles three cases:
--- 1. Both values specified: require exact match for either
--- 2. Only trueValue specified: match = true, any other value = false
--- 3. Only falseValue specified: match = false, any other value = true
---
--- Used by: availability parsing, relay state parsing, contact state parsing

--- @class StateParser
local StateParser = {}

--- Extract a value from a JSON table using JSONPath syntax.
--- Supports `$` root prefix, dot notation, and bracket array indexing.
---
--- @param jsonTable table The parsed JSON table.
--- @param jsonPath string JSONPath expression (e.g., "$.state.power" or "$.sensors[0].temp").
--- @return any|nil value The extracted value, or nil if path not found.
---
--- Examples:
--- ```lua
--- local t = { state = { power = "ON" }, sensors = { { temp = 72 } } }
--- StateParser.extractJsonPath(t, "$.state.power")   --> "ON"
--- StateParser.extractJsonPath(t, "$.sensors[0].temp") --> 72
--- StateParser.extractJsonPath(t, "$")                --> t (root)
--- StateParser.extractJsonPath(t, "$.missing")        --> nil
--- ```
function StateParser.extractJsonPath(jsonTable, jsonPath)
  if not jsonPath or jsonPath == "" or jsonPath == "$" then
    return jsonTable
  end

  if not string.match(jsonPath, "^%$") then
    return nil
  end

  local path = string.match(jsonPath, "^%$%.?(.*)$") or ""
  if path == "" then
    return jsonTable
  end

  local current = jsonTable
  for part in string.gmatch(path, "[^.]+") do
    if current == nil or type(current) ~= "table" then
      return nil
    end

    local field, index = string.match(part, "^([^%[]*)%[(%d+)%]$")
    if index then
      if field and field ~= "" then
        current = current[field]
        if current == nil or type(current) ~= "table" then
          return nil
        end
      end
      current = current[tonumber(index) + 1] -- Lua 1-indexed
    else
      current = current[part]
    end
  end

  return current
end

--- Parse a boolean state from payload using "match one, default other" logic.
---
--- @param payload string The payload to parse.
--- @param trueValue string|nil Value indicating true/on/open/available state.
--- @param falseValue string|nil Value indicating false/off/closed/unavailable state.
--- @return boolean|nil state True, false, or nil if cannot determine.
---
--- Examples:
--- ```lua
--- -- Both specified: require exact match
--- StateParser.parse("ON", "ON", "OFF")  --> true
--- StateParser.parse("OFF", "ON", "OFF") --> false
--- StateParser.parse("???", "ON", "OFF") --> nil (no match)
---
--- -- Only trueValue: match = true, else = false
--- StateParser.parse("online", "online", nil)  --> true
--- StateParser.parse("offline", "online", nil) --> false
---
--- -- Only falseValue: match = false, else = true
--- StateParser.parse("offline", nil, "offline") --> false
--- StateParser.parse("online", nil, "offline")  --> true
---
--- -- Neither specified: cannot determine
--- StateParser.parse("anything", nil, nil) --> nil
--- ```
function StateParser.parse(payload, trueValue, falseValue)
  -- Normalize empty strings to nil
  if trueValue == "" then
    trueValue = nil
  end
  if falseValue == "" then
    falseValue = nil
  end

  -- If both are specified, require exact match
  if trueValue ~= nil and falseValue ~= nil then
    if payload == trueValue then
      return true
    elseif payload == falseValue then
      return false
    end
    return nil
  end

  -- If only trueValue is specified: match = true, otherwise = false
  if trueValue ~= nil then
    return payload == trueValue
  end

  -- If only falseValue is specified: match = false, otherwise = true
  if falseValue ~= nil then
    return payload ~= falseValue
  end

  -- Neither specified, cannot determine
  return nil
end

return StateParser
