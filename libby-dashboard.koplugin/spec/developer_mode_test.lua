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
    }
end

local normal = KOReaderController.new{ settings_store = storeWith({ adobe_registration = { ok = true } }) }
normal:load()
assert(normal.settings.developer_mode == false)
normal:fulfill_acsm("book.acsm", "book.epub")
assert(captured_options.protected_epub == true, "normal mode must preserve DRM-protected EPUBs")

local developer = KOReaderController.new{ settings_store = storeWith({ developer_mode = true, adobe_registration = { ok = true } }) }
developer:load()
developer:fulfill_acsm("book.acsm", "book.epub")
assert(captured_options.protected_epub == false, "developer mode must save decrypted EPUBs")

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
