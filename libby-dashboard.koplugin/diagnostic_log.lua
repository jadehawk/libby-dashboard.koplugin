local DataStorage = require("datastorage")

local DiagnosticLog = {
    MAX_LOGS = 3,
    MAX_BYTES = 512 * 1024,
    _dir = nil,
    _path = nil,
}

local function safe_close(handle)
    if handle then pcall(handle.close, handle) end
end

local function file_size(path)
    local handle = io.open(path, "rb")
    if not handle then return 0 end
    local size = handle:seek("end") or 0
    safe_close(handle)
    return size
end

local function rotate_logs(dir)
    os.remove(dir .. "/libby-dashboard-3.log")
    os.rename(dir .. "/libby-dashboard-2.log", dir .. "/libby-dashboard-3.log")
    os.rename(dir .. "/libby-dashboard-1.log", dir .. "/libby-dashboard-2.log")
end

local function start_current_log(reason)
    local handle = io.open(DiagnosticLog._path, "w")
    if not handle then
        DiagnosticLog._path = nil
        return nil
    end
    handle:write(string.format(
        "%s [session] Libby Dashboard diagnostic log started | reason=%s\n",
        os.date("%Y-%m-%d %H:%M:%S"), tostring(reason or "startup")
    ))
    handle:flush()
    safe_close(handle)
    return DiagnosticLog._path
end

function DiagnosticLog.init()
    local util = require("util")
    local dir = DataStorage:getSettingsDir() .. "/libby-dashboard/logs"
    if not util.makePath(dir) then return nil end

    DiagnosticLog._dir = dir
    rotate_logs(dir)
    DiagnosticLog._path = dir .. "/libby-dashboard-1.log"
    return start_current_log("plugin-start")
end

function DiagnosticLog.path()
    return DiagnosticLog._path
end

function DiagnosticLog.log(event, details)
    if not DiagnosticLog._path then return false end

    if file_size(DiagnosticLog._path) >= DiagnosticLog.MAX_BYTES then
        rotate_logs(DiagnosticLog._dir)
        DiagnosticLog._path = DiagnosticLog._dir .. "/libby-dashboard-1.log"
        if not start_current_log("size-rotation") then return false end
    end

    local handle = io.open(DiagnosticLog._path, "a")
    if not handle then return false end

    local message = tostring(event or "event")
    if details ~= nil and details ~= "" then
        message = message .. " | " .. tostring(details)
    end
    message = message:gsub("[\r\n]+", " ")

    local ok = pcall(function()
        handle:write(string.format("%s %s\n", os.date("%Y-%m-%d %H:%M:%S"), message))
        handle:flush()
    end)
    safe_close(handle)
    return ok
end

return DiagnosticLog
