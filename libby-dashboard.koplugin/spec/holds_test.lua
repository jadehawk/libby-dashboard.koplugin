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

calls = {}
local borrowed, borrow_err = client:borrow_title("card-123", "title-456", "ebook", 14, false)
assert(type(borrowed) == "table", tostring(borrow_err))
assert(#calls == 1)
assert(calls[1].method == "POST")
assert(calls[1].path == "/card/card-123/loan/title-456")
assert(calls[1].json.period == 14 and calls[1].json.units == "days")
assert(calls[1].json.title_format == "ebook")
assert(calls[1].json.lucky_day == nil)

calls = {}
assert(client:borrow_title("card-123", "title-456", "ebook", 7, true))
assert(calls[1].json.lucky_day == 1)

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
            lendingPeriods = { book = { preference = { 14, "days" } } },
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
            holdListPosition = 12,
            estimatedWaitDays = 21,
            ownedCopies = 4,
            isAvailable = false,
            luckyDayAvailableCopies = 0,
            suspensionFlag = false,
            type = { id = "ebook" },
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
assert(normalized.holds[1].hold_list_position == 12)
assert(normalized.holds[1].estimated_wait_days == 21)
assert(normalized.holds[1].owned_copies == 4)
assert(normalized.holds[1].is_available == false)
assert(normalized.holds[1].suspension_flag == false)
assert(normalized.holds[1].borrow_format == "ebook")
assert(normalized.cards[1].lending_periods.book.preference[1] == 14)

local borrow_args
controller.settings.libby_snapshot = normalized
controller.libby_client = function()
    return { borrow_title = function(_, card_id, title_id, title_format, days, lucky_day)
        borrow_args = { card_id, title_id, title_format, days, lucky_day }
        return true
    end }
end
local borrow_ok, controller_borrow_err = controller:borrow_hold(normalized.holds[1])
assert(borrow_ok == true, tostring(controller_borrow_err))
assert(borrow_args[1] == "card-123" and borrow_args[2] == "title-456")
assert(borrow_args[3] == "ebook" and borrow_args[4] == 14 and borrow_args[5] == false)

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
assert(catalog_source:find('_("Borrow")', 1, true), "available hold action must offer Borrow")
assert(catalog_source:find('_("Read on Libby")', 1, true), "unsupported home-grid titles must read Read on Libby")
assert(catalog_source:find("self:coverStatusText(loan)", 1, true), "home grid must show per-cover status text")
assert(catalog_source:find('_("Close")', 1, true), "detail dismissal action must read Close")
assert(catalog_source:find('_("Book Notes")', 1, true), "every detail card must include Book Notes")
assert(catalog_source:find('_("Position: ")', 1, true), "hold detail must include queue position")
assert(catalog_source:find('_("Estimated wait: ")', 1, true), "hold detail must include estimated wait")
assert(catalog_source:find('_("#%d in line · %s")', 1, true), "hold cover status must combine position and wait")
assert(catalog_source:find('text = "#1000 in line · 365 days"', 1, true),
    "expanded list status column must reserve room for a realistic worst-case hold status")
assert(catalog_source:find("desired_loan_w = math.max(desired_loan_w, candidate_probe:getSize().w + 2 * pad)", 1, true),
    "expanded list status column must also grow for actual status text and translations")
assert(catalog_source:find("local loan_w = math.min(desired_loan_w, math.floor(width * 0.40))", 1, true),
    "expanded list status column must be allowed substantially more width without starving metadata")
assert(catalog_source:find("height = Screen:scaleBySize(36)", 1, true), "Book Notes display must reserve a compact two-line text area")
assert(catalog_source:find("content_h + action_band_h + 2 * Size.border.default", 1, true), "Hold and normal detail cards must size themselves from actual Notes-capable content")
assert(catalog_source:find("-- Notes are a book action, not a Hold-only action.", 1, true), "Book Notes action must be available for loans as well as Holds")
assert(catalog_source:find("local cover_reference_height = modal.height", 1, true), "notes-capable detail cards must retain the compact cover-height reference")
assert(catalog_source:find("cover_reference_height,", 1, true), "detail geometry must receive the compact cover reference")
assert(catalog_source:find("top_content = TopContainer:new", 1, true), "detail content must be top-aligned so the title cannot clip above the card")

local main_file = assert(io.open("libby-dashboard.koplugin/main.lua", "rb"))
local main_source = main_file:read("*a")
main_file:close()
assert(main_source:find("self.controller:cancel_hold(hold)", 1, true), "Cancel Hold UI must call the controller")
assert(main_source:find("self.controller:borrow_hold(hold)", 1, true), "Borrow UI must call the controller")
assert(main_source:find("self.controller:refresh_libby_snapshot()", 1, true), "Borrow UI must refresh Libby state before automatic download")
assert(main_source:find("self:downloadLoan(borrowed_loan, { from_borrow = true })", 1, true), "Borrow UI must automatically download the normalized new loan")
assert(main_source:find('_("Borrowed successfully, but automatic download failed.")', 1, true), "automatic download failure must preserve successful-borrow messaging")
assert(main_source:find("borrow_hold_callback = function(hold)", 1, true), "catalog must wire the Borrow callback")
assert(main_source:find('ok_text = _("Cancel Hold")', 1, true), "confirmation action must read Cancel Hold")
assert(main_source:find('title = _("Book Notes")', 1, true), "Book Notes editor must be wired")
assert(main_source:find("function LibbyDashboard:showBookNotes(item)", 1, true), "Book Notes editor must be general to Holds and loans")
assert(main_source:find("self.controller:set_book_note(item, value)", 1, true), "Book Notes editor must persist any title through the controller")

local note_store = {
    saved = nil,
    saveSetting = function(self, _, value) self.saved = value end,
    flush = function() end,
}
local note_controller = KOReaderController.new{ settings_store = note_store }
local note_hold = { id = "title-456", card_id = "card-123" }
local note_saved, note_err = note_controller:set_book_note(note_hold, " Recommended by Jane ")
assert(note_saved == true, tostring(note_err))
assert(note_controller:book_note(note_hold) == "Recommended by Jane")
local borrowed_same_title = { id = "title-456", card_id = "card-123", on_hold = false }
assert(note_controller:book_note(borrowed_same_title) == "Recommended by Jane", "Book Notes must survive Hold to borrowed-loan transition")
assert(note_store.saved.book_notes["card-123:title-456"] == "Recommended by Jane")
assert(note_controller:set_book_note(note_hold, "   ") == true)
assert(note_controller:book_note(note_hold) == nil, "blank Book Notes must remove the saved note")

print("holds_test: ok")
