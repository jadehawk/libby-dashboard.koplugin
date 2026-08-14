local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local LibbyBrowser = Menu:extend{
    title = _("Libby"),
    title_shrink_font_to_fit = true,
    title_bar_left_icon = "appbar.arrow.left",
    is_borderless = true,
    title_bar_fm_style = true,
}

function LibbyBrowser:init()
    self.item_table = self.item_table or {}
    Menu.init(self)
end

function LibbyBrowser:onLeftButtonTap()
    UIManager:close(self)
    return true
end

return LibbyBrowser
