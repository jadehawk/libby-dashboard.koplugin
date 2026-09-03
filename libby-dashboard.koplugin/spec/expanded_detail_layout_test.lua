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

local catalog_file = assert(io.open("libby-dashboard.koplugin/libby_catalog.lua", "rb"))
local catalog_source = catalog_file:read("*a")
catalog_file:close()
assert(catalog_source:find("TopFirstOverlapGroup", 1, true), "expanded overlay must dispatch input to the topmost painted layer first")
assert(catalog_source:find("stop_events_propagation = true", 1, true), "expanded detail layer must block gestures from reaching books behind it")
assert(catalog_source:find("ges.pos:notIntersectWith(modal_rect)", 1, true), "tapping outside the detail card must dismiss it")

print("expanded_detail_layout_test: ok")
