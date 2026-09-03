package.path = "./libby-dashboard.koplugin/?.lua;" .. package.path

local LibbyClient = require("libby_client")

local calls = {}
local transport = {}
function transport:request(request)
    calls[#calls + 1] = request
    return { status = 204, body = {} }
end

local client = LibbyClient.new{
    transport = transport,
    identity = "test-identity",
}

local ok, err = client:cancel_hold("card-123", "title-456")
assert(ok == true, tostring(err))
assert(#calls == 1)
assert(calls[1].method == "DELETE")
assert(calls[1].path == "/card/card-123/hold/title-456")
assert(calls[1].headers.Authorization == "Bearer test-identity")

local missing_card, missing_card_err = client:cancel_hold(nil, "title-456")
assert(missing_card == nil)
assert(missing_card_err == "Hold card id is missing")
assert(#calls == 1, "invalid hold cancellation must not make a network request")

local failing_transport = {}
function failing_transport:request(request)
    return { status = 409, body = {} }
end
local failing_client = LibbyClient.new{ transport = failing_transport, identity = "test-identity" }
local failed, failed_err = failing_client:cancel_hold("card-123", "title-456")
assert(failed == nil)
assert(failed_err == "Libby cancel hold failed with HTTP 409")

package.loaded["adobe_profile"] = {
    normalize = function(registration) return registration end,
    should_adopt_external = function() return false end,
}
package.loaded["datastorage"] = {}
package.loaded["luasettings"] = {}
package.loaded["rapidjson"] = {}
package.loaded["koreader_storage"] = { home_dir = function() return "/books" end }
package.loaded["koreader_transport"] = {}
package.loaded["path_template"] = {
    DEFAULT_TEMPLATE = "{title}",
    LEGACY_DEFAULT_TEMPLATE = "legacy",
    PREVIOUS_DEFAULT_TEMPLATE = "previous-default",
    validate = function() return true end,
}
package.loaded["koreader_controller"] = nil
local KOReaderController = require("koreader_controller")

local controller = setmetatable({
    settings = {
        extended_loan_time = false,
        downloaded_loans = {},
    },
}, KOReaderController)

local normalized, normalize_err = controller:normalize_libby_state({
    cards = {
        {
            id = "card-123",
            library = { name = "Internal Training Library" },
            counts = { hold = 2 },
            limits = { hold = 20 },
        },
    },
    loans = {
        {
            id = "loan-1",
            cardId = "card-123",
            title = "Borrowed Training Book",
            firstCreatorName = "Trainer One",
        },
    },
    holds = {
        {
            id = "title-456",
            cardId = "card-123",
            title = "Held Training Book",
            firstCreatorName = "Trainer Two",
            covers = { cover300Wide = { href = "https://example.invalid/held.jpg" } },
        },
    },
})
assert(normalized ~= nil, tostring(normalize_err))
assert(#normalized.cards == 1)
assert(normalized.cards[1].hold_count == 2)
assert(normalized.cards[1].hold_limit == 20)
assert(#normalized.loans == 1, "raw normalized loans must remain active-loan-only")
assert(#normalized.holds == 1)
assert(normalized.holds[1].id == "title-456")
assert(normalized.holds[1].card_id == "card-123")
assert(normalized.holds[1].library == "Internal Training Library")
assert(normalized.holds[1].title == "Held Training Book")
assert(normalized.holds[1].author == "Trainer Two")
assert(normalized.holds[1].cover_url == "https://example.invalid/held.jpg")
assert(normalized.holds[1].on_hold == true)

local catalog = controller:catalog_snapshot(normalized)
assert(catalog ~= normalized)
assert(#normalized.loans == 1, "catalog merge must not mutate the raw active-loan list")
assert(#catalog.loans == 2, "catalog must contain active loans plus holds")
local hold_found = false
for _, item in ipairs(catalog.loans) do
    if item.on_hold == true then
        hold_found = true
        assert(item.id == "title-456")
        assert(item.card_id == "card-123")
    end
end
assert(hold_found, "catalog must include the normalized hold")

local catalog_file = assert(io.open("libby-dashboard.koplugin/libby_catalog.lua", "rb"))
local catalog_source = catalog_file:read("*a")
catalog_file:close()
assert(catalog_source:find('_("On Hold")', 1, true), "hold status must read On Hold")
assert(catalog_source:find("HOLDS_ICON_PATH", 1, true), "expanded header must include Holds icon")
assert(catalog_source:find('_("Refreshing…")', 1, true), "expanded header must expose refresh feedback")
assert(catalog_source:find('_("Cancel Hold")', 1, true), "hold action must read Cancel Hold")

local main_file = assert(io.open("libby-dashboard.koplugin/main.lua", "rb"))
local main_source = main_file:read("*a")
main_file:close()
assert(main_source:find("self.controller:cancel_hold(hold)", 1, true), "Cancel Hold UI must call the controller")
assert(main_source:find('ok_text = _("Cancel Hold")', 1, true), "confirmation action must read Cancel Hold")

print("holds_test: ok")
