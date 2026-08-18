package.path = "./libby-dashboard.koplugin/?.lua;" .. package.path

local root = "/tmp/libby-dashboard-raw-sync-test"
os.execute("rm -rf '" .. root .. "'")
os.execute("mkdir -p '" .. root .. "/libby-dashboard/debug'")

local encoded_state
package.loaded["adobe_profile"] = { should_adopt_external = function() return false end }
package.loaded["datastorage"] = { getSettingsDir = function() return root end }
package.loaded["luasettings"] = {}
package.loaded["rapidjson"] = {
    encode = function(state)
        encoded_state = state
        return '{"loans":[{"id":"loan-1","unknown":{"reader":"bsreader","formatId":"mystery-format"}}]}'
    end,
}
package.loaded["koreader_storage"] = { home_dir = function() return "/books" end }
package.loaded["koreader_transport"] = {}
package.loaded["libby_client"] = {}
package.loaded["libby_state"] = {}
package.loaded["loan_model"] = { list = function() return {} end, card_name = function() return "Library" end }
package.loaded["path_template"] = {
    DEFAULT_TEMPLATE = "{title}",
    LEGACY_DEFAULT_TEMPLATE = "legacy",
    validate = function() return true end,
}
package.loaded["util"] = { makePath = function() return true end }

package.loaded["koreader_controller"] = nil
local Controller = require("koreader_controller")
local controller = Controller.new{}

local raw = {
    cards = {},
    loans = {
        {
            id = "loan-1",
            unknown = {
                reader = "bsreader",
                formatId = "mystery-format",
            },
        },
    },
}

local archive, latest = controller:save_raw_libby_sync(raw)
assert(archive and latest)
assert(encoded_state == raw, "raw sync state must be encoded before normalization")
assert(encoded_state.loans[1].unknown.reader == "bsreader")
assert(encoded_state.loans[1].unknown.formatId == "mystery-format")

local latest_file = assert(io.open(latest, "rb"))
local latest_contents = latest_file:read("*a")
latest_file:close()
assert(latest_contents:find('"reader":"bsreader"', 1, true))
assert(latest_contents:find('"formatId":"mystery-format"', 1, true))

local archive_file = assert(io.open(archive, "rb"))
assert(archive_file:read("*a") == latest_contents)
archive_file:close()

os.remove(latest)
controller.libby_authenticated = function() return true end
controller.libby_client = function()
    return { sync = function() return raw end }
end
local synced, sync_err = controller:sync_libby()
assert(synced == raw, tostring(sync_err))
local synced_latest = assert(io.open(root .. "/libby-dashboard/debug/libby-sync-latest.json", "rb"))
assert(synced_latest:read("*a"):find('"reader":"bsreader"', 1, true))
synced_latest:close()

os.execute("rm -rf '" .. root .. "'")
print("raw_libby_sync_capture_test: ok")
