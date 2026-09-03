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
package.loaded["adobe.adobe"] = {}
package.loaded["adobe.fulfillment"] = {}

package.loaded["koreader_controller"] = nil
local KOReaderController = require("koreader_controller")

local function storeWith(value)
    return {
        readSetting = function() return value end,
        saveSetting = function(self, _, saved) self.saved = saved end,
        flush = function() end,
    }
end

local default_controller = KOReaderController.new{ settings_store = storeWith({}) }
default_controller:load()
assert(default_controller.settings.extended_loan_time == true, "Extended Loan Time must default ON")

local store = storeWith({
    migration_index = 2,
    downloaded_loans = {
        ["loan-retained"] = {
            loan_id = "loan-retained",
            card_id = "card-1",
            title = "Retained Training Book",
            author = "Trainer",
            authors = { "Trainer" },
            series = "Training Series",
            series_index = 2,
            library = "Internal Training Library",
            path = "/books/retained.epub",
            adobe_format = "ebook-epub-adobe",
            media_type = "ebook",
            expires_at = os.time() - 60,
        },
    },
})
local controller = KOReaderController.new{ settings_store = store }
controller:load()

assert(controller:set_extended_loan_time(true) == true)
assert(controller.settings.extended_loan_time == true)
assert(store.saved and store.saved.extended_loan_time == true, "Extended Loan Time setting must persist")

local snapshot = {
    cards = { { id = "card-1", library = { name = "Internal Training Library" } } },
    loans = {},
}
local merged = controller:catalog_snapshot(snapshot)
assert(merged ~= snapshot, "Extended Loan catalog should be a merged view")
assert(#merged.loans == 1, "server-missing tracked book must remain in catalog")
local retained = merged.loans[1]
assert(retained.id == "loan-retained")
assert(retained.card_id == "card-1", "retained book must remain attached to its original library")
assert(retained.library == "Internal Training Library")
assert(retained.extended_loan == true)
assert(retained.title == "Retained Training Book")
assert(retained.series == "Training Series")
assert(retained.cover_url == nil, "legacy tracked loans may not have persisted cover URLs")
assert(controller:refresh_downloaded_loan_metadata({
    id = "loan-retained",
    cover_url = "https://example.invalid/cover.jpg",
    expires_at = os.time() - 60,
}) == true)
assert(controller:downloaded_loan("loan-retained").cover_url == "https://example.invalid/cover.jpg", "Return Early metadata refresh must backfill legacy cover URLs")

local remove_calls = 0
local ok, removed, candidates = controller:reconcile_downloaded_loans(snapshot, function()
    remove_calls = remove_calls + 1
    return true
end)
assert(ok == true)
assert(removed == 0, "Extended Loan Time must suppress automatic local deletion")
assert(candidates == 0)
assert(remove_calls == 0)
assert(controller:downloaded_loan("loan-retained") ~= nil, "retained download record must survive reconciliation")

local active_snapshot = {
    cards = snapshot.cards,
    loans = {
        {
            id = "loan-retained",
            card_id = "card-1",
            title = "Retained Training Book",
            author = "Trainer",
            library = "Internal Training Library",
            adobe_format = "ebook-epub-adobe",
            media_type = "ebook",
            expires_at = os.time() - 60,
            days_remaining = 0,
        },
    },
}
local active_merged = controller:catalog_snapshot(active_snapshot)
assert(#active_merged.loans == 1)
assert(active_merged.loans[1].extended_loan == true, "expired active server loan must become Extended Loan")
assert(active_merged.loans[1].days_remaining == nil, "Extended Loan must not display normal days remaining")

assert(controller:delete_downloaded_loan("loan-retained") == true)
assert(controller:downloaded_loan("loan-retained") == nil, "Delete must clear only the local tracking record")
assert(#controller:catalog_snapshot(snapshot).loans == 0, "deleted retained book must disappear from merged catalog")

local off_store = storeWith({
    migration_index = 2,
    extended_loan_time = false,
    downloaded_loans = {
        ["loan-expired"] = {
            loan_id = "loan-expired",
            card_id = "card-1",
            title = "Expired Book",
            path = "/books/expired.epub",
            expires_at = os.time() - 60,
        },
    },
})
local off = KOReaderController.new{ settings_store = off_store }
off:load()
local off_catalog = off:catalog_snapshot(snapshot)
assert(#off_catalog.loans == #snapshot.loans, "OFF must preserve the normal active-loan catalog")
for _, item in ipairs(off_catalog.loans) do
    assert(item.extended_loan ~= true, "OFF must not synthesize Extended Loans")
end
local off_remove_calls = 0
local off_ok, off_removed, off_candidates = off:reconcile_downloaded_loans(snapshot, function(record)
    off_remove_calls = off_remove_calls + 1
    assert(record.loan_id == "loan-expired")
    return true
end)
assert(off_ok == true)
assert(off_removed == 1)
assert(off_candidates == 1)
assert(off_remove_calls == 1, "normal cleanup must still remove expired/server-missing downloads")
assert(off:downloaded_loan("loan-expired") == nil)

local renewed = KOReaderController.new{ settings_store = storeWith({
    migration_index = 2,
    extended_loan_time = false,
    downloaded_loans = {
        ["loan-renewed"] = {
            loan_id = "loan-renewed",
            path = "/books/renewed.epub",
            expires_at = os.time() - 60,
        },
    },
}) }
renewed:load()
local renewed_remove_calls = 0
local renewed_ok, renewed_removed, renewed_candidates = renewed:reconcile_downloaded_loans({
    loans = { { id = "loan-renewed", expires_at = os.time() + 86400 } },
}, function()
    renewed_remove_calls = renewed_remove_calls + 1
    return true
end)
assert(renewed_ok == true)
assert(renewed_removed == 0 and renewed_candidates == 0, "current live renewal expiry must override an older tracked expiry")
assert(renewed_remove_calls == 0)

local main = assert(io.open("./libby-dashboard.koplugin/main.lua", "rb")):read("*a")
assert(main:find("function LibbyDashboard:deleteExtendedLoan", 1, true))
assert(main:find("self:removeTrackedBook(record)", 1, true), "Delete must reuse history-preserving cleanup")
assert(main:find("self.controller:delete_downloaded_loan(loan.id)", 1, true), "Delete must clear the local tracking record")
assert(main:find("self.controller:return_loan(loan)", 1, true), "Return Early must keep the normal server return flow")
assert(main:find("self.controller:refresh_downloaded_loan_metadata(loan)", 1, true), "Return Early must persist current loan metadata before server removal")
assert(main:find("local cache_key = loan.id or loan.title or loan.cover_url", 1, true), "cached covers must remain addressable by stable loan id")
assert(not main:find("or not loan.cover_url then return nil end", 1, true), "legacy retained loans must not require a persisted cover URL to reuse cached covers")

print("extended_loan_time_test: ok")
