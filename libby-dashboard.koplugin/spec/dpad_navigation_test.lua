package.path = "./libby-dashboard.koplugin/?.lua;" .. package.path

local Dpad = require("libby_dpad")

local items = {
    { id = "a" }, { id = "b" }, { id = "c" }, { id = "d" },
    { id = "e" }, { id = "f" }, { id = "g" }, { id = "h" },
    { id = "i" }, { id = "j" },
}
local function key(item) return item.id end
local function has_binding(bindings, wanted)
    for _, binding in ipairs(bindings or {}) do
        for _, value in ipairs(binding or {}) do
            if value == wanted then return true end
        end
    end
    return false
end

assert(Dpad.find_index(items, "f", key) == 6)
assert(Dpad.find_index(items, "missing", key) == 1)
assert(Dpad.page_for(1, 8) == 1)
assert(Dpad.page_for(9, 8) == 2)
assert(Dpad.first_index_for_page(2, 8, #items) == 9)

local fake_non_touch = {
    isTouchDevice = function() return false end,
    input = { group = {
        Back = "GROUP_BACK", PgBack = "GROUP_PGBACK", PgFwd = "GROUP_PGFWD",
        Up = "GROUP_UP", Down = "GROUP_DOWN", Left = "GROUP_LEFT", Right = "GROUP_RIGHT",
        Press = "GROUP_PRESS", Enter = "GROUP_ENTER", Menu = "GROUP_MENU",
    } },
}
local fake_touch = { isTouchDevice = function() return true end }
assert(Dpad.is_touch_device(fake_non_touch) == false)
assert(Dpad.is_touch_device(fake_touch) == true)

-- Use event names that cannot shadow InputContainer:onKeyPress(), KOReader's raw
-- hardware dispatcher. This collision previously made every Kindle D-pad key
-- activate the focused Settings icon.
local events = Dpad.catalog_key_events(fake_non_touch)
for _, alias in ipairs({ "Back", "Escape", "Esc", "GROUP_BACK" }) do
    assert(has_binding(events.DpadBack, alias), "missing back alias " .. alias)
end
for _, alias in ipairs({ "Press", "Enter", "Return", "Select", "GROUP_PRESS", "GROUP_ENTER" }) do
    assert(has_binding(events.DpadPress, alias), "missing select alias " .. alias)
end
for _, alias in ipairs({ "Up", "GROUP_UP" }) do assert(has_binding(events.DpadUp, alias)) end
for _, alias in ipairs({ "Down", "GROUP_DOWN" }) do assert(has_binding(events.DpadDown, alias)) end
for _, alias in ipairs({ "Left", "GROUP_LEFT" }) do assert(has_binding(events.DpadLeft, alias)) end
for _, alias in ipairs({ "Right", "GROUP_RIGHT" }) do assert(has_binding(events.DpadRight, alias)) end
for _, alias in ipairs({ "PgUp", "PgBack", "Prev", "LPgBack", "RPgBack", "GROUP_PGBACK" }) do
    assert(has_binding(events.DpadPrevPage, alias), "missing previous-page alias " .. alias)
end
for _, alias in ipairs({ "PgDn", "PgFwd", "Next", "LPgFwd", "RPgFwd", "GROUP_PGFWD" }) do
    assert(has_binding(events.DpadNextPage, alias), "missing next-page alias " .. alias)
end
assert(has_binding(events.DpadMenu, "Menu"))
assert(has_binding(events.DpadMenu, "F10"))
assert(has_binding(events.DpadMenu, "GROUP_MENU"))

local dialog_events = Dpad.dialog_key_events(fake_non_touch)
assert(has_binding(dialog_events.DpadPress, "Select"), "dialogs must support Kindle Select")
assert(has_binding(dialog_events.DpadPress, "Return"), "dialogs must support Return")
assert(has_binding(dialog_events.DpadBack, "Escape"), "dialogs must support Escape")
assert(has_binding(dialog_events.DpadUp, "GROUP_UP"), "dialogs must bind device directional groups")

-- libbee-style page-local movement: vertical motion stays on-page, while
-- horizontal movement at the visible edge can request an adjacent page.
local next_index, page_delta = Dpad.move_page_local(3, "right", 4, 1, 8, #items)
assert(next_index == 4 and page_delta == 0)
next_index, page_delta = Dpad.move_page_local(8, "right", 4, 1, 8, #items)
assert(next_index == 9 and page_delta == 1)
next_index, page_delta = Dpad.move_page_local(9, "left", 4, 2, 8, #items)
assert(next_index == 1 and page_delta == -1)
next_index, page_delta = Dpad.move_page_local(2, "down", 4, 1, 8, #items)
assert(next_index == 6 and page_delta == 0)
next_index, page_delta = Dpad.move_page_local(6, "down", 4, 1, 8, #items)
assert(next_index == 6 and page_delta == 0, "Down must not silently cross pages")

-- Disabled/blank actions (e.g. Holds in a synthetic rack) must never become a
-- D-pad focus stop.
local actions = { function() end, false, function() end, false, function() end }
assert(Dpad.active_action_index(actions, 2) == 3)
assert(Dpad.next_action_index(actions, 1, 1) == 3)
assert(Dpad.next_action_index(actions, 3, 1) == 5)
assert(Dpad.next_action_index(actions, 5, 1) == 1)
assert(Dpad.next_action_index(actions, 1, -1) == 5)

local visual_positions = {
    [1] = { row = 1, column = 1 },
    [2] = { row = 1, column = 2 },
    [3] = { row = 2, column = 1 },
}
assert(Dpad.move_visual_grid(visual_positions, 1, "right") == 2)
assert(Dpad.move_visual_grid(visual_positions, 2, "right") == 2, "Right must not jump across a library divider")
assert(Dpad.move_visual_grid(visual_positions, 2, "down") == 3, "Down should choose the closest item in the next library row")
assert(Dpad.move_visual_grid(visual_positions, 3, "up") == 1)

local file = assert(io.open("libby-dashboard.koplugin/libby_catalog.lua", "rb"))
local source = file:read("*a")
file:close()

assert(source:find('self.key_focus_active = not Dpad.is_touch_device(Device)', 1, true),
    "non-touch devices must start with visible D-pad focus")
assert(source:find('self.key_focus_region = self.key_focus_active and "books" or nil', 1, true),
    "non-touch startup must target books, not Settings")
assert(source:find('self.key_focus_waiting_for_items = true', 1, true),
    "empty cached startup must remember to focus the first item after refresh")
assert(source:find('if self.key_focus_waiting_for_items and #items > 0 then', 1, true),
    "live refresh must recover item focus after an initially empty shelf")
assert(source:find('self.key_events = Dpad.catalog_key_events(Device)', 1, true),
    "catalog must use the libbee-compatible hardware key map")
assert(not source:find('function LibbyCatalog:onKeyPress(', 1, true),
    "catalog must never override InputContainer:onKeyPress raw dispatch")
assert(source:find('function LibbyCatalog:onDpadPress()', 1, true),
    "center/select activation must use a non-framework event handler")
assert(source:find('Dpad.move_page_local(', 1, true), "grid navigation must use page-local movement")
assert(source:find('if self.browser_view_mode == "list" then', 1, true),
    "browser list must have dedicated hardware navigation")
assert(source:find('return self:enterKeyHeaderFocus', 1, true),
    "Up from the first visible item must enter header focus")
assert(source:find('Dpad.next_action_index(actions, header_index', 1, true),
    "header navigation must skip disabled controls")
assert(source:find('function LibbyCatalog:cycleBrowserScope()', 1, true), "Swap must cycle browser scopes")
assert(source:find('function LibbyCatalog:onDpadBack()', 1, true), "browser must provide hardware Back")
assert(source:find('elseif self.close_callback then', 1, true), "Back at browser root must exit the plugin")
assert(source:find('return _("Listen on Libby")', 1, true), "audiobooks must use Listen on Libby wording")

local settings_file = assert(io.open("libby-dashboard.koplugin/settings_dialog.lua", "rb"))
local settings_source = settings_file:read("*a")
settings_file:close()
assert(settings_source:find('dialog.key_events = Dpad.dialog_key_events(Device)', 1, true),
    "custom Settings shell must register hardware key events")
assert(not settings_source:find('dialog.onKeyPress =', 1, true),
    "Settings must not override the raw InputContainer key dispatcher")
for _, handler in ipairs({ "onDpadBack", "onDpadUp", "onDpadDown", "onDpadLeft", "onDpadRight", "onDpadPress" }) do
    assert(settings_source:find('dialog.' .. handler .. ' = function()', 1, true),
        "Settings is missing hardware handler " .. handler)
end
assert(settings_source:find('focus_zone = "nav"', 1, true), "Settings must expose a navigable category rail")
assert(settings_source:find('focus_zone = #content_actions > 0 and "content" or "close"', 1, true),
    "Settings Right must enter content or Close")
assert(settings_source:find('local extended_focus_index = #content_actions + 1', 1, true),
    "Extended Loan Time checkbox must be reachable from hardware focus")

print("dpad_navigation_test: ok")
