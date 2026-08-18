package.path = "./libby-dashboard.koplugin/?.lua;" .. package.path

local UpdatePolicy = require("update_policy")

local function newer(candidate, current)
    local function parse(version)
        local a, b, c = version:match("^(%d+)%.(%d+)%.(%d+)$")
        return tonumber(a), tonumber(b), tonumber(c)
    end
    local a, b, c = parse(candidate)
    local x, y, z = parse(current)
    if a ~= x then return a > x end
    if b ~= y then return b > y end
    return c > z
end

assert(UpdatePolicy.should_prompt("0.2.5", "0.2.4", nil, newer) == true)
assert(UpdatePolicy.should_prompt("0.2.5", "0.2.4", "0.2.5", newer) == false)
assert(UpdatePolicy.should_prompt("0.2.6", "0.2.4", "0.2.5", newer) == true)
assert(UpdatePolicy.should_prompt("0.2.4", "0.2.4", nil, newer) == false)
assert(UpdatePolicy.should_prompt("0.2.3", "0.2.4", nil, newer) == false)
assert(UpdatePolicy.should_prompt(nil, "0.2.4", nil, newer) == false)

print("update_policy_test: ok")
