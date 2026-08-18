package.path = "./libby-dashboard.koplugin/?.lua;" .. package.path

local RefreshWatchdog = require("refresh_watchdog")

local function newUI()
    local ui = { scheduled = {}, unscheduled = {} }
    function ui:scheduleIn(delay, callback)
        self.scheduled[#self.scheduled + 1] = { delay = delay, callback = callback }
    end
    function ui:unschedule(callback)
        self.unscheduled[#self.unscheduled + 1] = callback
    end
    return ui
end

do
    local owner, ui = {}, newUI()
    local fired = 0
    local token = RefreshWatchdog.arm(owner, ui, function() fired = fired + 1 end)
    assert(ui.scheduled[1].delay == RefreshWatchdog.TIMEOUT)
    assert(owner._refresh_network_watchdog == token)
    token()
    assert(fired == 1)
    assert(owner._refresh_network_watchdog == nil)
end

do
    local owner, ui = {}, newUI()
    local fired = 0
    local first = RefreshWatchdog.arm(owner, ui, function() fired = fired + 1 end)
    local second = RefreshWatchdog.arm(owner, ui, function() fired = fired + 10 end)
    assert(ui.unscheduled[1] == first)
    first()
    assert(fired == 0)
    second()
    assert(fired == 10)
end

do
    local owner, ui = {}, newUI()
    local fired = 0
    local token = RefreshWatchdog.arm(owner, ui, function() fired = fired + 1 end)
    assert(RefreshWatchdog.cancel(owner, ui, token) == true)
    assert(owner._refresh_network_watchdog == nil)
    token()
    assert(fired == 0)
end

print("refresh_watchdog_test: ok")
