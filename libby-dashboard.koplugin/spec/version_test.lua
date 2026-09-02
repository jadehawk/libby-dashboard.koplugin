package.path = "./libby-dashboard.koplugin/?.lua;" .. package.path

local Version = require("libby_dashboard_version")

local function assert_parts(value, expected)
    local parts = assert(Version.parse(value), "expected valid version: " .. tostring(value))
    for index = 1, 4 do
        assert(parts[index] == expected[index], string.format("%s part %d mismatch", value, index))
    end
end

assert_parts("0.2.6", { 0, 2, 6, 0 })
assert_parts("0.2.6.1", { 0, 2, 6, 1 })
assert_parts("v1.10.3.12", { 1, 10, 3, 12 })
assert(Version.parse("0.2") == nil)
assert(Version.parse("0.2.6.1.4") == nil)
assert(Version.parse("v0.2.x.1") == nil)

assert(Version.is_newer("0.2.6.1", "0.2.6") == true)
assert(Version.is_newer("0.2.6", "0.2.6.1") == false)
assert(Version.is_newer("0.2.7", "0.2.6.9") == true)
assert(Version.is_newer("1.0.0", "0.99.99.99") == true)
assert(Version.is_newer("0.2.6.1", "0.2.6.1") == false)
assert(Version.is_newer("bad", "0.2.6") == false)

print("version_test: ok")
