package.path = "./libby-dashboard.koplugin/?.lua;" .. package.path

local UpdatePolicy = require("update_policy")
local Version = require("libby_dashboard_version")

local newer = Version.is_newer

assert(UpdatePolicy.should_prompt("0.2.5", "0.2.4", nil, newer) == true)
assert(UpdatePolicy.should_prompt("0.2.5", "0.2.4", "0.2.5", newer) == false)
assert(UpdatePolicy.should_prompt("0.2.6", "0.2.4", "0.2.5", newer) == true)
assert(UpdatePolicy.should_prompt("0.2.8.0", "0.2.8", nil, newer) == true)
assert(UpdatePolicy.should_prompt("0.2.8.0", "0.2.8", "0.2.8.0", newer) == false)
assert(UpdatePolicy.should_prompt("0.2.4", "0.2.4", nil, newer) == false)
assert(UpdatePolicy.should_prompt("0.2.3", "0.2.4", nil, newer) == false)
assert(UpdatePolicy.should_prompt(nil, "0.2.4", nil, newer) == false)

print("update_policy_test: ok")
