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
package.loaded["loan_model"] = {
    list = function()
        return { { id = "loan-1", non_adobe_format_label = "Kindle / Libby App" } }
    end,
    card_name = function() return "Library" end,
}
package.loaded["path_template"] = {
    DEFAULT_TEMPLATE = "{title}",
    LEGACY_DEFAULT_TEMPLATE = "legacy",
    validate = function() return true end,
}
package.loaded["util"] = { makePath = function() return true end }
package.loaded["libs/libkoreader-lfs"] = {
    dir = function(path)
        local pipe = assert(io.popen("ls -1 '" .. path .. "'"))
        local names = { ".", ".." }
        for name in pipe:lines() do table.insert(names, name) end
        pipe:close()
        local index = 0
        return function()
            index = index + 1
            return names[index]
        end
    end,
}

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

local original_date = os.date
os.date = function() return "20260818-080000" end

local normalized = assert(controller:normalize_libby_state(raw))
assert(normalized.loans[1].non_adobe_format_label == "Kindle / Libby App", "normalized snapshot must preserve non-Adobe format label")

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

for _ = 1, 4 do assert(controller:save_raw_libby_sync(raw)) end

local archive_names = {}
local iterator = package.loaded["libs/libkoreader-lfs"].dir(root .. "/libby-dashboard/debug")
for name in iterator do
    if name:match("^libby%-sync%-%d%d%d%d%d%d%d%d%-%d%d%d%d%d%d%-?%d*%.json$") then
        table.insert(archive_names, name)
    end
end
table.sort(archive_names)
assert(#archive_names == 3, "raw sync capture must keep only 3 historical archives")
assert(archive_names[1] == "libby-sync-20260818-080000-3.json")
assert(archive_names[2] == "libby-sync-20260818-080000-4.json")
assert(archive_names[3] == "libby-sync-20260818-080000-5.json")
assert(io.open(latest, "rb"), "latest sync capture must be preserved")

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

os.date = original_date
os.execute("rm -rf '" .. root .. "'")
print("raw_libby_sync_capture_test: ok")
