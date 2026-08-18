package.path = "./libby-dashboard.koplugin/?.lua;" .. package.path

local root = "/tmp/libby-dashboard-diagnostic-log-test"
os.execute("rm -rf " .. root)

package.loaded["datastorage"] = {
    getSettingsDir = function() return root end,
}
package.loaded["util"] = {
    makePath = function(path)
        return os.execute("mkdir -p '" .. path .. "'") == 0
    end,
}
package.loaded["diagnostic_log"] = nil

local DiagnosticLog = require("diagnostic_log")
local logs_dir = root .. "/libby-dashboard/logs"

assert(DiagnosticLog.init() == logs_dir .. "/libby-dashboard-1.log")
assert(DiagnosticLog.log("first-event", "details"))

local handle = assert(io.open(logs_dir .. "/libby-dashboard-1.log", "r"))
local content = handle:read("*a")
handle:close()
assert(content:match("first%-event"))
assert(content:match("details"))

DiagnosticLog.init()
DiagnosticLog.init()
DiagnosticLog.init()
assert(io.open(logs_dir .. "/libby-dashboard-1.log", "r"))
assert(io.open(logs_dir .. "/libby-dashboard-2.log", "r"))
assert(io.open(logs_dir .. "/libby-dashboard-3.log", "r"))
assert(io.open(logs_dir .. "/libby-dashboard-4.log", "r") == nil)

DiagnosticLog.MAX_BYTES = 1
assert(DiagnosticLog.log("rotation-event"))
handle = assert(io.open(logs_dir .. "/libby-dashboard-1.log", "r"))
content = handle:read("*a")
handle:close()
assert(content:match("size%-rotation"))
assert(content:match("rotation%-event"))

os.execute("rm -rf " .. root)
print("diagnostic_log_test: ok")
