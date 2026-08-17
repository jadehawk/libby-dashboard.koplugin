package.path = "./libby-dashboard.koplugin/?.lua;" .. package.path

local encoded_payload
package.loaded["account_backup"] = {
    create_metadata = function(label)
        assert(label == "Jimmy's Kindle")
        return { label = label, created_at = "2026-08-17T15:30:42Z", backup_id = "backup-id-1" }
    end,
    filename = function(metadata)
        assert(metadata.backup_id == "backup-id-1")
        return "libby-dashboard-account-backup-jimmys-kindle-20260817153042.json"
    end,
    encode = function(payload, password, metadata)
        assert(password == "backup-pass")
        assert(metadata.label == "Jimmy's Kindle")
        encoded_payload = payload
        return "ENCRYPTED-BACKUP"
    end,
    decode = function(contents, password)
        assert(contents == "ENCRYPTED-BACKUP")
        assert(password == "backup-pass")
        return encoded_payload
    end,
    inspect = function(contents)
        if contents == "ENCRYPTED-BACKUP" then
            return { version = 2, label = "Jimmy's Kindle", created_at = "2026-08-17T15:30:42Z", backup_id = "backup-id-1" }
        elseif contents == "SECOND-BACKUP" then
            return { version = 2, label = "Karen's Boox Go7", created_at = "2026-08-16T09:20:00Z", backup_id = "backup-id-2" }
        elseif contents == "V1-BACKUP" then
            return { version = 1 }
        end
    end,
}
package.loaded["adobe_profile"] = {
    normalize = function(registration)
        if type(registration) ~= "table" then return nil, "bad registration" end
        return registration
    end,
    summary = function(registration) return { registered = registration ~= nil } end,
    should_adopt_external = function() return false end,
}
package.loaded["datastorage"] = { getSettingsDir = function() return "/tmp/koreader-settings" end }
package.loaded["luasettings"] = {}
package.loaded["rapidjson"] = {}
package.loaded["koreader_storage"] = {
    home_dir = function() return "/tmp/libby-dashboard-account-test/home" end,
}
package.loaded["koreader_transport"] = {}
package.loaded["libby_client"] = {}
package.loaded["libby_state"] = { is_authenticated = function(state) return type(state.libby_identity) == "string" and state.libby_identity ~= "" end }
package.loaded["loan_model"] = {}
package.loaded["path_template"] = {
    DEFAULT_TEMPLATE = "{home}/Libby Books/{author:first}/{title}.{ext}",
    LEGACY_DEFAULT_TEMPLATE = "legacy",
    validate = function() return true end,
}
package.loaded["util"] = {
    makePath = function(path)
        os.execute("mkdir -p '" .. path .. "'")
        return true
    end,
}
package.loaded["libs/libkoreader-lfs"] = {
    dir = function(path)
        local pipe = assert(io.popen("ls -1A '" .. path .. "' 2>/dev/null"))
        local entries = { ".", ".." }
        for name in pipe:lines() do table.insert(entries, name) end
        pipe:close()
        local i = 0
        return function()
            i = i + 1
            return entries[i]
        end
    end,
}

os.execute("rm -rf /tmp/koreader-settings/libby-dashboard /tmp/libby-dashboard-account-test")
os.execute("mkdir -p '/tmp/libby-dashboard-account-test/home/Libby Books'")

package.loaded["koreader_controller"] = nil
local Controller = require("koreader_controller")

local persisted
local store = {
    readSetting = function() return nil end,
    saveSetting = function(_, _, value) persisted = value end,
    flush = function() end,
}
local controller = Controller.new{ settings_store = store }
controller:load()
controller.settings.libby_identity = "libby-token"
controller.settings.adobe_registration = { user = "adept-user" }

assert(controller:account_backup_dir() == "/tmp/koreader-settings/libby-dashboard/backups")
assert(controller:configured_book_storage_root() == "/tmp/libby-dashboard-account-test/home/Libby Books")
local search_dirs = controller:account_backup_search_dirs()
assert(#search_dirs == 3)
assert(search_dirs[1].location == "Settings")
assert(search_dirs[2].location == "Home")
assert(search_dirs[3].location == "Book storage")

local path, metadata_or_err = controller:export_account_backup("Jimmy's Kindle", "backup-pass")
assert(path, metadata_or_err)
assert(path == "/tmp/koreader-settings/libby-dashboard/backups/libby-dashboard-account-backup-jimmys-kindle-20260817153042.json")
assert(encoded_payload.backup.label == "Jimmy's Kindle")
assert(encoded_payload.libby.identity == "libby-token")
assert(encoded_payload.adobe.registration.user == "adept-user")
local exported = assert(io.open(path, "rb"))
assert(exported:read("*a") == "ENCRYPTED-BACKUP")
exported:close()
local found = controller:find_account_backups()
assert(#found == 1)
assert(found[1].path == path)
assert(found[1].label == "Jimmy's Kindle")
assert(found[1].location == "Settings")

controller.settings.libby_identity = nil
controller.settings.adobe_registration = nil
controller.settings.libby_snapshot = { stale = true }
local restored, restore_err = controller:import_account_backup("backup-pass", path)
assert(restored, restore_err)
assert(restored.libby == true and restored.adobe == true)
assert(controller.settings.libby_identity == "libby-token")
assert(controller.settings.adobe_registration.user == "adept-user")
assert(controller.settings.libby_snapshot == nil)
assert(persisted.libby_identity == "libby-token")

-- The same backup copied to another discovery folder is deduplicated by backup_id.
local duplicate_path = "/tmp/libby-dashboard-account-test/home/libby-dashboard-account-backup-jimmys-kindle-copy.json"
local duplicate = assert(io.open(duplicate_path, "wb")); duplicate:write("ENCRYPTED-BACKUP"); duplicate:close()
found = controller:find_account_backups()
assert(#found == 1)
os.remove(duplicate_path)

-- A different backup is shown separately with its own label/date/location.
local second_path = "/tmp/libby-dashboard-account-test/home/Libby Books/libby-dashboard-account-backup-karens-boox-20260816092000.json"
local second = assert(io.open(second_path, "wb")); second:write("SECOND-BACKUP"); second:close()
found = controller:find_account_backups()
assert(#found == 2)
assert(found[1].label == "Jimmy's Kindle")
assert(found[2].label == "Karen's Boox Go7")
assert(found[2].location == "Book storage")
os.remove(second_path)

-- Existing encrypted v1 filename is still discovered, but plaintext/other names are ignored.
local v1_path = "/tmp/libby-dashboard-account-test/home/libby-dashboard-account-backup.json"
local v1 = assert(io.open(v1_path, "wb")); v1:write("V1-BACKUP"); v1:close()
local plaintext_path = "/tmp/libby-dashboard-account-test/home/libby-dashboard-adobe-bytebooks-auth.json"
local plaintext = assert(io.open(plaintext_path, "wb")); plaintext:write("PLAINTEXT"); plaintext:close()
found = controller:find_account_backups()
assert(#found == 2)
local saw_v1 = false
for _, backup in ipairs(found) do
    if backup.path == v1_path then
        saw_v1 = true
        assert(backup.label == "Unlabeled Account Backup")
        assert(backup.version == 1)
    end
end
assert(saw_v1)
os.remove(v1_path)
os.remove(plaintext_path)

controller.settings.book_path_template = "{home}/{author:first}/{title}.{ext}"
local deduped = controller:account_backup_search_dirs()
assert(#deduped == 2, "storage root equal to HOME must be deduplicated")

os.remove(path)
os.execute("rm -rf /tmp/koreader-settings/libby-dashboard /tmp/libby-dashboard-account-test")
print("account_restore_test: ok")
