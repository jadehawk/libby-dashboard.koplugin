local path = "libby-dashboard.koplugin/main.lua"
local file = assert(io.open(path, "rb"))
local source = file:read("*a")
file:close()

assert(source:find('local Dispatcher = require%("dispatcher"%)'), "main.lua must load KOReader Dispatcher")
assert(source:find('Dispatcher:registerAction%("libby_dashboard_open"'), "Libby Dashboard gesture action must be registered")
assert(source:find('event = "LibbyDashboardOpen"'), "gesture action must dispatch LibbyDashboardOpen")
assert(source:find('title = _%("Libby Dashboard: open dashboard"%)'), "gesture action must have a user-visible title")
assert(source:find('general = true'), "gesture action must be available in Gesture Manager General actions")
assert(source:find('self:onDispatcherRegisterActions%(%)%s+self%.ui%.menu:registerToMainMenu%(self%)'), "init must register Dispatcher actions before the main menu, matching KOReader plugin lifecycle practice")
assert(source:find('function LibbyDashboard:onLibbyDashboardOpen%(%)%s+self:showBrowser%(%)'), "gesture event must open the existing dashboard browser")

print("gesture_action_test: ok")
