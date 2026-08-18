local NetworkAction = {}

NetworkAction.IDLE_TIMEOUT = 300

local function cancelExpiry(owner, ui_manager)
    if owner._network_lease_expire_action then
        ui_manager:unschedule(owner._network_lease_expire_action)
        owner._network_lease_expire_action = nil
    end
end

function NetworkAction.touch(owner, manager, ui_manager)
    if not owner._network_lease_active then return end

    cancelExpiry(owner, ui_manager)
    local expire
    expire = function()
        if owner._network_lease_expire_action ~= expire then return end
        owner._network_lease_expire_action = nil
        owner._network_lease_active = nil
        manager:afterWifiAction()
    end
    owner._network_lease_expire_action = expire
    ui_manager:scheduleIn(NetworkAction.IDLE_TIMEOUT, expire)
end

function NetworkAction.run(owner, manager, ui_manager, callback, require_online)
    local runner = require_online == false and manager.runWhenConnected or manager.runWhenOnline
    return runner(manager, function()
        owner._network_lease_active = true
        NetworkAction.touch(owner, manager, ui_manager)
        local ok, result = pcall(callback)
        NetworkAction.touch(owner, manager, ui_manager)
        if not ok then error(result, 0) end
        return result
    end)
end

function NetworkAction.release(owner, manager, ui_manager)
    cancelExpiry(owner, ui_manager)
    if not owner._network_lease_active then return end
    owner._network_lease_active = nil
    manager:afterWifiAction()
end

return NetworkAction
