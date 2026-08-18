package.path = "./libby-dashboard.koplugin/?.lua;" .. package.path

package.loaded["adobe_profile"] = {
    normalize = function(registration)
        if not registration then return nil, "missing registration" end
        return registration
    end,
    should_adopt_external = function() return false end,
}
package.loaded["datastorage"] = {}
package.loaded["luasettings"] = {}
package.loaded["rapidjson"] = {}
package.loaded["koreader_storage"] = { home_dir = function() return "/books" end }
package.loaded["koreader_transport"] = {}
package.loaded["libby_client"] = {}
package.loaded["libby_state"] = {}
package.loaded["loan_model"] = {}
package.loaded["path_template"] = {
    DEFAULT_TEMPLATE = "{title}",
    LEGACY_DEFAULT_TEMPLATE = "legacy",
    PREVIOUS_DEFAULT_TEMPLATE = "previous-default",
    validate = function() return true end,
}
package.loaded["adobe.adobe"] = {
    restoreActivation = function(profile)
        return {
            creds = {},
            deviceUUID = "device",
            fingerprint = "fingerprint",
            authCert = "cert",
        }
    end,
}

local captured_options
package.loaded["adobe.fulfillment"] = {
    process = function(_, _, _, _, _, _, options)
        captured_options = options
        return { ok = true }
    end,
}

package.loaded["koreader_controller"] = nil
local KOReaderController = require("koreader_controller")

local function storeWith(value)
    return {
        readSetting = function() return value end,
        saveSetting = function(self, _, saved) self.saved = saved end,
        flush = function() end,
    }
end

local normal = KOReaderController.new{ settings_store = storeWith({ adobe_registration = { ok = true } }) }
normal:load()
assert(normal.settings.developer_mode == false)
normal:fulfill_acsm("book.acsm", "book.epub")
assert(captured_options.protected_epub == true, "normal mode must preserve DRM-protected EPUBs")
local resolver = function() return "resolved.epub" end
normal:fulfill_acsm("book.acsm", nil, { resolve_output_path = resolver })
assert(captured_options.protected_epub == true, "adding a destination resolver must preserve normal protected mode")
assert(captured_options.resolve_output_path == resolver)

local developer = KOReaderController.new{ settings_store = storeWith({ developer_mode = true, adobe_registration = { ok = true } }) }
developer:load()
developer:fulfill_acsm("book.acsm", "book.epub")
assert(captured_options.protected_epub == false, "developer mode must save decrypted EPUBs")

local old_store = storeWith({ book_path_template = "previous-default", adobe_registration = { ok = true } })
local old_default = KOReaderController.new{ settings_store = old_store }
old_default:load()
assert(old_default.settings.book_path_template == "{title}", "migration 1 must force the current built-in path template")
assert(old_default.settings.migration_index == 1, "migration 1 must be marked applied")
assert(old_store.saved and old_store.saved.migration_index == 1, "migration 1 must persist during startup")

local custom = KOReaderController.new{ settings_store = storeWith({ migration_index = 1, book_path_template = "custom-template", adobe_registration = { ok = true } }) }
custom:load()
assert(custom.settings.book_path_template == "custom-template", "an already-migrated custom path must not be reset")

local migrated = KOReaderController.new{ settings_store = storeWith({ cleanup_mode = "dry_run", adobe_registration = { ok = true } }) }
migrated:load()
assert(migrated.settings.developer_mode == true, "legacy dry-run state must migrate to developer mode")
migrated:fulfill_acsm("book.acsm", "book.epub")
assert(captured_options.protected_epub == false)

local explicit = KOReaderController.new{ settings_store = storeWith({ developer_mode = true, adobe_registration = { ok = true } }) }
explicit:load()
explicit:fulfill_acsm("book.acsm", "book.epub", { protected_epub = true })
assert(captured_options.protected_epub == true, "explicit fulfillment options must still override developer defaults")

print("developer_mode_test: ok")
