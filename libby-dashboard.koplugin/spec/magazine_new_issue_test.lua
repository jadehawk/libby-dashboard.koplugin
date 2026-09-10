package.path = "./libby-dashboard.koplugin/?.lua;" .. package.path

package.loaded["adobe_profile"] = {
    normalize = function(registration) return registration end,
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
package.loaded["adobe.adobe"] = {}
package.loaded["adobe.fulfillment"] = {}

package.loaded["koreader_controller"] = nil
local KOReaderController = require("koreader_controller")
local MediaRacks = require("libby_media_racks")

local function storeWith(value)
    return {
        readSetting = function() return value end,
        saveSetting = function(self, _, saved) self.saved = saved end,
        flush = function() end,
    }
end

local store = storeWith({ migration_index = 2 })
local controller = KOReaderController.new{ settings_store = store }
controller:load()
assert(type(controller.settings.magazine_seen_issues) == "table",
    "magazine seen-state must have a persistent settings map")

local first = {
    magazine_subscriptions = {
        {
            id = "issue-1",
            parent_magazine_title_id = "parent-1",
            title = "Weekly Test",
            media_type = "magazine",
            magazine_frequency = "Weekly",
        },
    },
}
assert(controller:save_libby_snapshot(first) == true)
assert(controller.settings.magazine_seen_issues["parent-1"] == "issue-1",
    "first successful rack sync must seed the current issue as already seen")
assert(first.magazine_subscriptions[1].magazine_new_issue == false,
    "first successful rack sync must not mark every existing subscription NEW")

local second = {
    magazine_subscriptions = {
        {
            id = "issue-2",
            parent_magazine_title_id = "parent-1",
            title = "Weekly Test",
            media_type = "magazine",
            magazine_frequency = "Weekly",
        },
    },
}
assert(controller:save_libby_snapshot(second) == true)
assert(controller.settings.magazine_seen_issues["parent-1"] == "issue-1",
    "detecting a newer issue must not acknowledge it automatically")
assert(second.magazine_subscriptions[1].magazine_new_issue == true,
    "a changed current issue id must be marked NEW")

local delivered = MediaRacks.magazines({
    loans = {
        {
            id = "issue-2",
            parent_magazine_title_id = "parent-1",
            title = "Weekly Test",
            library = "Library One",
            media_type = "magazine",
        },
    },
    magazine_subscriptions = second.magazine_subscriptions,
})
assert(#delivered == 1, "auto-delivered current issue must not duplicate its subscription entry")
assert(delivered[1].rack_source == "loan", "matching live loan should remain the rendered rack item")
assert(delivered[1].magazine_subscription == true, "live current issue must inherit subscription state")
assert(delivered[1].magazine_new_issue == true, "auto-delivered current issue must preserve NEW state")
assert(delivered[1].magazine_frequency == "Weekly", "live current issue should inherit subscription frequency")

local stale = MediaRacks.magazines({
    loans = {
        {
            id = "issue-1",
            parent_magazine_title_id = "parent-1",
            title = "Old Weekly Test",
            library = "Library One",
            media_type = "magazine",
        },
    },
    magazine_subscriptions = second.magazine_subscriptions,
})
assert(#stale == 1 and stale[1].id == "issue-2",
    "an older live magazine loan must not displace the subscription's newer current issue")
assert(stale[1].rack_source == "subscription")

assert(controller:acknowledge_magazine_issue(delivered[1]) == true)
assert(controller.settings.magazine_seen_issues["parent-1"] == "issue-2",
    "opening the new issue must persist it as seen")
assert(controller.settings.libby_snapshot.magazine_subscriptions[1].magazine_new_issue == false,
    "acknowledging a new issue must clear NEW in the cached snapshot")

local catalog_file = assert(io.open("libby-dashboard.koplugin/libby_catalog.lua", "rb"))
local catalog_source = catalog_file:read("*a")
catalog_file:close()
assert(catalog_source:find('if loan.magazine_new_issue == true then return _("NEW ISSUE") end', 1, true),
    "Magazine Rack cover status must prioritize NEW ISSUE")
assert(catalog_source:find('return loan.magazine_frequency', 1, true),
    "seen magazine issues should show their delivery frequency")
assert(catalog_source:find('local acknowledged = self.magazine_acknowledge_callback', 1, true),
    "opening magazine details must acknowledge NEW state through persistence callback")

local main_file = assert(io.open("libby-dashboard.koplugin/main.lua", "rb"))
local main_source = main_file:read("*a")
main_file:close()
assert(main_source:find('magazine_acknowledge_callback = function(item)', 1, true))
assert(main_source:find('return self.controller:acknowledge_magazine_issue(item)', 1, true),
    "catalog acknowledgment callback must report persistence success")

print("magazine_new_issue_test: ok")
