local RefreshWatchdog = {}

RefreshWatchdog.TIMEOUT = 50

function RefreshWatchdog.cancel(owner, ui_manager, token)
    local current = owner._refresh_network_watchdog
    if not current or (token and current ~= token) then return false end
    ui_manager:unschedule(current)
    owner._refresh_network_watchdog = nil
    return true
end

function RefreshWatchdog.arm(owner, ui_manager, callback)
    RefreshWatchdog.cancel(owner, ui_manager)
    local token
    token = function()
        if owner._refresh_network_watchdog ~= token then return end
        owner._refresh_network_watchdog = nil
        callback()
    end
    owner._refresh_network_watchdog = token
    ui_manager:scheduleIn(RefreshWatchdog.TIMEOUT, token)
    return token
end

return RefreshWatchdog
