package.path = "./libby-dashboard.koplugin/?.lua;" .. package.path

local Dpad = require("libby_dpad")

local loans = {
    { id = "a" }, { id = "b" }, { id = "c" }, { id = "d" },
    { id = "e" }, { id = "f" }, { id = "g" }, { id = "h" },
    { id = "i" },
}
local function key(loan) return loan.id end

assert(Dpad.find_index(loans, "f", key) == 6)
assert(Dpad.find_index(loans, "missing", key) == 1)
assert(Dpad.move_grid(1, "right", 4, #loans) == 2)
assert(Dpad.move_grid(2, "left", 4, #loans) == 1)
assert(Dpad.move_grid(2, "down", 4, #loans) == 6)
assert(Dpad.move_grid(6, "up", 4, #loans) == 2)
assert(Dpad.move_grid(8, "down", 4, #loans) == 9)
assert(Dpad.page_for(1, 8) == 1)
assert(Dpad.page_for(9, 8) == 2)
assert(Dpad.first_index_for_page(2, 8, #loans) == 9)

local file = assert(io.open("libby-dashboard.koplugin/libby_catalog.lua", "rb"))
local source = file:read("*a")
file:close()

assert(source:find('self.key_focus_active = false', 1, true), "catalog must not auto-focus on open")
assert(source:find('Device.input.group', 1, true), "catalog must bind KOReader device input groups")
assert(source:find('KeyPress = { { "Press" }, { "Enter" } }', 1, true), "catalog must support Press and Enter")
assert(source:find('KeyPrevPage = { { "PgBack" } }', 1, true), "catalog must support page back")
assert(source:find('KeyNextPage = { { "PgFwd" } }', 1, true), "catalog must support page forward")
assert(source:find('focused = self:isKeyFocusedLoan(loan)', 1, true), "grid cards must render D-pad focus")
assert(source:find('self.key_focus_active = false\r\n    self.key_focus_index = nil\r\n    self.selected_loan_id = loanKey(loan)', 1, true)
    or source:find('self.key_focus_active = false\n    self.key_focus_index = nil\n    self.selected_loan_id = loanKey(loan)', 1, true),
    "touch selection must clear D-pad focus")
assert(source:find('function LibbyCatalog:keyHeaderActions()', 1, true), "actionable header icons must have a D-pad action model")
assert(source:find('self.key_focus_region = "header"', 1, true), "D-pad must support a header focus region")
assert(source:find('if direction == "up" and index_on_page <= self:keyFocusColumns() then', 1, true),
    "Up from the first visible book row must enter the header")
assert(source:find('if self.key_focus_region == "header" then', 1, true), "Press and directional keys must handle header focus")
assert(source:find('bordersize = focused and focus_border or 0', 1, true), "focused header icons must render a visible focus border")
assert(source:find('local SWAP_ICON_PATH = plugin_root and (plugin_root .. "/dependencies/icons/swap.svg") or nil', 1, true),
    "expanded library header must use swap.svg")
assert(source:find('function LibbyCatalog:cycleExpandedLibraryScope()', 1, true), "Swap must cycle library scope")
assert(source:find('self:selectCard(scopes[next_index], true)', 1, true), "Swap must preserve header focus while changing libraries")
assert(source:find('-- Swap + title + two blank icon slots + Refresh + Holds + View + Close.', 1, true),
    "expanded header must keep the requested Swap / spacing / action order")
assert(source:find('local focus_inset = math.max(1, Size.border.thin)', 1, true),
    "header focus borders must be inset so they do not overwrite the header separator")
assert(source:find('self:isKeyHeaderActionFocused(5)', 1, true), "all five expanded-header action icons must be D-pad focusable")

print("dpad_navigation_test: ok")
