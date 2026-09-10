package.path = "./libby-dashboard.koplugin/?.lua;" .. package.path

local MediaRacks = require("libby_media_racks")

assert(MediaRacks.ALL_SCOPE == "__all__")
assert(MediaRacks.AUDIOBOOKS_SCOPE == "__audiobooks__")
assert(MediaRacks.MAGAZINE_SCOPE == "__magazine_rack__")
assert(MediaRacks.is_synthetic(MediaRacks.AUDIOBOOKS_SCOPE))
assert(MediaRacks.is_synthetic(MediaRacks.MAGAZINE_SCOPE))
assert(not MediaRacks.is_synthetic(MediaRacks.ALL_SCOPE))

local snapshot = {
    loans = {
        { id = "ebook-1", title = "Book", library = "Alpha", media_type = "ebook" },
        { id = "audio-2", title = "Zulu Audio", library = "Beta", media_type = "audiobook" },
        { id = "audio-1", title = "Alpha Audio", library = "Alpha", media_type = "audiobook" },
        { id = "audio-hold", title = "Held Audio", library = "Alpha", media_type = "audiobook", on_hold = true },
        { id = "mag-shared", title = "Borrowed Current Issue", library = "Beta", media_type = "magazine", days_remaining = 7 },
        { id = "mag-loan", title = "Borrowed Magazine", library = "Alpha", media_type = "magazine", days_remaining = 5 },
        { id = "mag-hold", title = "Held Magazine", library = "Alpha", media_type = "magazine", on_hold = true },
    },
    magazine_subscriptions = {
        { id = "mag-shared", title = "Subscription Duplicate", library = "Beta", magazine_frequency = "Monthly" },
        { id = "mag-sub", title = "Current Subscription Issue", library = "Alpha", edition = "September 2026", magazine_frequency = "Monthly" },
    },
}

local audio = MediaRacks.audiobooks(snapshot)
assert(#audio == 2, "audiobook rack should include active audiobook loans only")
assert(audio[1].id == "audio-1" and audio[2].id == "audio-2", "audiobook rack should sort by library/title")
assert(audio[1].rack_source == "loan" and audio[1].rack_group == "Alpha")

local magazines = MediaRacks.magazines(snapshot)
assert(#magazines == 3, "magazine rack should combine active loans and subscription current issues")
local by_id = {}
for _, item in ipairs(magazines) do by_id[item.id] = item end
assert(by_id["mag-shared"].title == "Borrowed Current Issue", "active magazine loan must win subscription dedupe")
assert(by_id["mag-shared"].rack_source == "loan")
assert(by_id["mag-sub"].media_type == "magazine")
assert(by_id["mag-sub"].magazine_subscription == true)
assert(by_id["mag-sub"].rack_source == "subscription")
assert(by_id["mag-sub"].rack_group == "Alpha")
assert(by_id["mag-hold"] == nil, "magazine holds must not appear in Magazine Rack")

local groups = MediaRacks.page_groups(magazines, 1, #magazines)
assert(#groups == 2, "synthetic rack must expose one group per source library")
assert(groups[1].key == "Alpha" and groups[1].count == 2 and #groups[1].entries == 2)
assert(groups[2].key == "Beta" and groups[2].count == 1 and #groups[2].entries == 1)
local positions, visual_rows = MediaRacks.grid_positions(magazines, 1, #magazines, 4)
assert(visual_rows == 2, "each source library must start on its own grid row")
assert(positions[1].row == 1 and positions[1].column == 1)
assert(positions[2].row == 1 and positions[2].column == 2)
assert(positions[3].row == 2 and positions[3].column == 1)

local scopes = MediaRacks.scope_ids({ { id = 101 }, { cardId = "202" } }, snapshot)
assert(table.concat(scopes, ",") == "101,202,__all__,__audiobooks__,__magazine_rack__",
    "browser scope order must be physical libraries, All, Audiobooks, Magazine Rack")

local ebook_only = {
    loans = { { id = "ebook", media_type = "ebook" } },
    magazine_subscriptions = {},
}
local simple_scopes = MediaRacks.scope_ids({ { id = "card" } }, ebook_only)
assert(table.concat(simple_scopes, ",") == "card,__all__", "empty synthetic racks should not be shown")

local catalog_file = assert(io.open("libby-dashboard.koplugin/libby_catalog.lua", "rb"))
local catalog_source = catalog_file:read("*a")
catalog_file:close()
assert(catalog_source:find('if MediaRacks.is_synthetic(self.selected_scope_id) then', 1, true),
    "synthetic racks must be first-class browser scopes")
assert(catalog_source:find('return _("Magazine Rack"), #loans', 1, true), "Magazine Rack title must be visible")
assert(catalog_source:find('return _("Audiobooks"), #loans', 1, true), "Audiobooks title must be visible")
assert(catalog_source:find('local scopes = MediaRacks.scope_ids(cards, self.snapshot)', 1, true),
    "Swap must cycle through media racks")
assert(catalog_source:find('self.settings.libby_browser_scope_id = self.selected_scope_id or MediaRacks.ALL_SCOPE', 1, true),
    "last browser scope must persist")
assert(catalog_source:find('not MediaRacks.is_synthetic(self.selected_scope_id) and function() self:toggleBrowserHolds() end or false', 1, true),
    "Holds filtering must be disabled in synthetic racks")
assert(catalog_source:find('local function rackGroupHeaderWidget(', 1, true),
    "Magazine/Audiobook racks must render source-library divider rows")
assert(catalog_source:find('rackGroupHeaderWidget(group.key, group.count', 1, true),
    "library divider must include each source library item count")
assert(catalog_source:find('local positions, book_rows, groups = MediaRacks.grid_positions(', 1, true),
    "synthetic grid must start each source library on a fresh visual row")
assert(catalog_source:find('loan.magazine_subscription ~= true', 1, true),
    "subscription-current issues must not expose Return")
assert(catalog_source:find('action = actionButton(_("Libby Info")', 1, true),
    "unsupported rack media must expose an explicit Libby information action")
assert(catalog_source:find('_("Current subscription issue")', 1, true),
    "subscription current issues need a useful detail status")
assert(catalog_source:find('return _("Listen on Libby")', 1, true),
    "audiobook cards must say Listen on Libby")
assert(catalog_source:find('secondary_text = safeText(loan.edition or loan.publish_date, 90)', 1, true),
    "magazine list rows should show edition or published date instead of author")
assert(not catalog_source:find('safeText(loan.author or _("N/A"), 90)', 1, true),
    "list rows must not force an N/A author placeholder")

-- Approved root header order: Swap | centered name | Holds | Refresh | Settings | Grid/List | Close.
local swap_pos = assert(catalog_source:find('iconTap(SWAP_ICON_PATH', 1, true))
local holds_pos = assert(catalog_source:find('filterIconTap(HOLDS_ICON_PATH', swap_pos, true))
local refresh_pos = assert(catalog_source:find('iconTap(REFRESH_ICON_PATH', holds_pos, true))
local settings_pos = assert(catalog_source:find('iconTap(SETTINGS_ICON_PATH', refresh_pos, true))
local toggle_pos = assert(catalog_source:find('iconTap(toggle_icon', settings_pos, true))
local close_pos = assert(catalog_source:find('iconTap(CLOSE_ICON_PATH', toggle_pos, true))
assert(swap_pos < holds_pos and holds_pos < refresh_pos and refresh_pos < settings_pos and settings_pos < toggle_pos and toggle_pos < close_pos,
    "root browser header icon order changed unexpectedly")

local main_file = assert(io.open("libby-dashboard.koplugin/main.lua", "rb"))
local main_source = main_file:read("*a")
main_file:close()
assert(main_source:find('function LibbyDashboard:showLibbyMediaInfo(item)', 1, true),
    "Libby media information callback must be implemented")
assert(main_source:find('libby_media_callback = function(item)', 1, true),
    "catalog Libby media action must be wired to the plugin")
assert(main_source:find('collect(snapshot.magazine_subscriptions)', 1, true),
    "cover prefetch must include subscription-only Magazine Rack issues")
assert(main_source:find('if item.cover_url and key and not seen[key]', 1, true),
    "cover prefetch should deduplicate loan/subscription overlap by stable item id")

print("media_racks_test: ok")
