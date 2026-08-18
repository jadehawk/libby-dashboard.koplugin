package.path = "./libby-dashboard.koplugin/?.lua;" .. package.path

local NetworkAction = require("network_action")

local calls = {}
local manager = {}
local ui = { scheduled = {} }

function manager:runWhenOnline(callback)
    calls[#calls + 1] = "online"
    return callback()
end

function manager:runWhenConnected(callback)
    calls[#calls + 1] = "connected"
    return callback()
end

function manager:afterWifiAction()
    calls[#calls + 1] = "after"
end

function ui:scheduleIn(seconds, action)
    calls[#calls + 1] = "schedule:" .. tostring(seconds)
    self.scheduled[action] = true
end

function ui:unschedule(action)
    if self.scheduled[action] then
        self.scheduled[action] = nil
        calls[#calls + 1] = "unschedule"
        return true
    end
    return false
end

local owner = {}
NetworkAction.run(owner, manager, ui, function()
    calls[#calls + 1] = "action"
end)
assert(owner._network_lease_active == true)
assert(table.concat(calls, ",") == "online,schedule:300,action,unschedule,schedule:300")
assert(not table.concat(calls, ","):find("after", 1, true))

local first_expiry = owner._network_lease_expire_action
calls = {}
NetworkAction.run(owner, manager, ui, function()
    calls[#calls + 1] = "second"
end)
local second_expiry = owner._network_lease_expire_action
assert(first_expiry ~= second_expiry)
assert(table.concat(calls, ",") == "online,unschedule,schedule:300,second,unschedule,schedule:300")
first_expiry()
assert(owner._network_lease_active == true)
assert(not table.concat(calls, ","):find("after", 1, true))

calls = {}
second_expiry()
assert(owner._network_lease_active == nil)
assert(table.concat(calls, ",") == "after")

calls = {}
NetworkAction.run(owner, manager, ui, function()
    calls[#calls + 1] = "connected-action"
end, false)
assert(calls[1] == "connected")
NetworkAction.release(owner, manager, ui)
assert(table.concat(calls, ","):find("after", 1, true))
assert(owner._network_lease_active == nil)
assert(owner._network_lease_expire_action == nil)

calls = {}
local ok, err = pcall(function()
    NetworkAction.run(owner, manager, ui, function()
        error("network action failure", 0)
    end)
end)
assert(ok == false)
assert(err == "network action failure")
assert(owner._network_lease_active == true)
assert(not table.concat(calls, ","):find("after", 1, true))
NetworkAction.release(owner, manager, ui)
assert(table.concat(calls, ","):find("after", 1, true))

print("network_action_test: ok")
