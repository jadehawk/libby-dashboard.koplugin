package.path = "./libby-dashboard.koplugin/?.lua;" .. package.path

local Layout = require("libby_catalog_layout")
local identity_scale = function(value) return value end

assert(Layout.isTallPortrait(945, 2048) == true, "Galaxy-class tall portrait screens must use the tall detail layout")
assert(Layout.isTallPortrait(574, 780) == false, "KOReader emulator proportions must keep the compact detail layout")
assert(Layout.isTallPortrait(1404, 1872) == false, "typical e-reader portrait proportions must keep the compact detail layout")
assert(Layout.isTallPortrait(2048, 945) == false, "landscape screens must not use tall portrait layout")

local galaxy_modal = Layout.expandedModalGeometry(945, 2048, identity_scale)
assert(galaxy_modal.tall == true)
assert(galaxy_modal.width >= 860 and galaxy_modal.width < 945, "tall modal should use most, but not all, of the phone width")
assert(galaxy_modal.height < 2048 * 0.40, "tall modal height must be width-constrained instead of blindly using 40% of screen height")

local galaxy_detail = Layout.expandedDetailGeometry(
    galaxy_modal.width,
    galaxy_modal.height,
    4,
    34,
    8,
    3,
    identity_scale,
    true
)
assert(galaxy_detail.tall == true)
assert(galaxy_detail.cover_width <= math.floor(galaxy_modal.width * 0.38), "tall cover must never dominate the card width")
assert(galaxy_detail.action_width > galaxy_detail.info_width, "tall layout actions must span the card instead of the metadata column")
assert(galaxy_detail.button_width >= 250, "Galaxy-class tall layout must leave readable width for three action buttons")

local emulator_modal = Layout.expandedModalGeometry(574, 780, identity_scale)
assert(emulator_modal.tall == false)
local emulator_detail = Layout.expandedDetailGeometry(
    emulator_modal.width,
    emulator_modal.height,
    4,
    34,
    8,
    3,
    identity_scale,
    false
)
assert(emulator_detail.button_width >= 100, "compact layout must still reserve readable action-button width")
assert(emulator_detail.action_width > emulator_detail.info_width, "normal grid/list detail actions must span the full card width below cover + metadata")
assert(emulator_detail.top_height < emulator_modal.height, "normal grid/list detail must reserve a separate bottom action band")
assert(emulator_detail.cover_width > 0 and emulator_detail.cover_height > 0)

local emulator_four_button_detail = Layout.expandedDetailGeometry(
    emulator_modal.width,
    emulator_modal.height,
    4,
    34,
    8,
    4,
    identity_scale,
    false
)
assert(emulator_four_button_detail.cover_width == emulator_detail.cover_width,
    "adding a fourth bottom action must not shrink the detail cover")

local catalog_file = assert(io.open("libby-dashboard.koplugin/libby_catalog.lua", "rb"))
local catalog_source = catalog_file:read("*a")
catalog_file:close()
assert(catalog_source:find("TopFirstOverlapGroup", 1, true), "expanded overlay must dispatch input to the topmost painted layer first")
assert(catalog_source:find("stop_events_propagation = true", 1, true), "expanded detail layer must block gestures from reaching books behind it")
assert(catalog_source:find("ges.pos:notIntersectWith(modal_rect)", 1, true), "tapping outside the detail card must dismiss it")

assert(catalog_source:find("local top_inset = math.max(5, Screen:scaleBySize(5))", 1, true), "all detail cards must keep at least a five-pixel top border gap")
assert(catalog_source:find("table.insert(content_stack, VerticalSpan:new{ width = top_inset })", 1, true), "normal and Hold detail content must share the real KOReader top inset")
assert(catalog_source:find("dimen = Geom:new{ w = cover_w, h = top_row_h }", 1, true), "cover must live in its own top-aligned row cell")
assert(catalog_source:find("local cover_top_inset = math.max(1, Screen:scaleBySize(1))", 1, true), "cover should only add a tiny inset beyond the shared card gap")
assert(catalog_source:find("VerticalSpan:new{ width = cover_top_inset }", 1, true), "cover top inset must be applied inside the cover cell")
assert(catalog_source:find("local compact_trim = math.max(2, Screen:scaleBySize(4))", 1, true), "detail metadata must trim KOReader's default line boxes")
assert(catalog_source:find("local notes = VerticalGroup:new{ align = \"left\" }", 1, true), "Book Notes must be a separate full-width section")
assert(catalog_source:find("VerticalSpan:new{ width = math.max(2, Screen:scaleBySize(2)) }", 1, true), "Book Notes must keep a compact separation from the action band")
assert(not catalog_source:find("VerticalSpan:new{ height =", 1, true), "VerticalSpan spacers must use width, because KOReader ignores height for this widget")
assert(catalog_source:find('then return loanTimeText(loan) end', 1, true), "downloaded cover status must show remaining loan time")
assert(not catalog_source:find('return _("Download")', 1, true), "Download must remain an action and never be used as a cover-state caption")
assert(catalog_source:find('if loan and loan.extended_loan == true then return loanTimeText(loan) end', 1, true), "Extended Loan cover status must describe state rather than local availability")
assert(catalog_source:find("local action_band_h = action_h + math.max(4, Screen:scaleBySize(4))", 1, true), "action band must stay content-sized instead of consuming leftover modal height")
assert(catalog_source:find("content_h + action_band_h + 2 * Size.border.default", 1, true), "detail card height must be derived from actual content")
assert(catalog_source:find("local detail_size = detail:getSize()", 1, true), "detail hit rectangle must follow the content-sized visible card")
assert(not catalog_source:find("height - geometry.top_height", 1, true), "detail actions must never be centered inside leftover fixed-height space")

print("expanded_detail_layout_test: ok")
