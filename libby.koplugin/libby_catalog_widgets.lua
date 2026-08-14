local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local _ = require("gettext")

local LibbyListItem = InputContainer:extend{
    entry = nil,
    dimen = nil,
    menu = nil,
}

local function safeText(value, max_len)
    local text = tostring(value or "")
    text = text:gsub("[%z\1-\31\127]", " "):gsub("%s+", " ")
    if #text <= max_len then return text end
    return text:sub(1, math.max(1, max_len - 3)) .. "..."
end

function LibbyListItem:init()
    self.ges_events = {
        TapSelect = {
            GestureRange:new{ ges = "tap", range = self.dimen },
        },
        HoldSelect = {
            GestureRange:new{ ges = "hold", range = self.dimen },
        },
    }

    local entry = self.entry or {}
    local separator_h = Size.line.medium
    local inner_h = math.max(1, self.dimen.h - separator_h)
    local pad = Size.padding.small
    local text_w = math.max(1, self.dimen.w - 2 * pad)
    local title_h = math.max(1, math.floor(inner_h * 0.58))
    local subtitle_h = math.max(1, inner_h - title_h)

    local title = safeText(entry.text or _("Untitled"), 96)
    local subtitle = safeText(entry.mandatory or "", 96)

    local content = VerticalGroup:new{ align = "left" }
    table.insert(content, TextBoxWidget:new{
        text = BD.auto(title),
        width = text_w,
        height = title_h,
        height_adjust = true,
        alignment = "left",
        bold = true,
        face = Font:getFace("cfont", 20),
        height_overflow_show_ellipsis = true,
    })
    if subtitle ~= "" then
        table.insert(content, TextBoxWidget:new{
            text = BD.auto(subtitle),
            width = text_w,
            height = subtitle_h,
            height_adjust = true,
            alignment = "left",
            face = Font:getFace("cfont", 16),
            height_overflow_show_ellipsis = true,
        })
    end
    table.insert(content, LineWidget:new{
        background = Blitbuffer.COLOR_LIGHT_GRAY,
        dimen = Geom:new{ w = self.dimen.w, h = separator_h },
    })

    self[1] = FrameContainer:new{
        width = self.dimen.w,
        height = self.dimen.h,
        margin = 0,
        padding = pad,
        bordersize = 0,
        content,
    }
end

function LibbyListItem:onTapSelect()
    if self.menu and self.menu.onMenuSelect then
        self.menu:onMenuSelect(self.entry)
    end
    return true
end

function LibbyListItem:onHoldSelect()
    if self.menu and self.menu.onMenuHoldSelect then
        self.menu:onMenuHoldSelect(self.entry)
    elseif self.menu and self.menu.onMenuSelect then
        self.menu:onMenuSelect(self.entry)
    end
    return true
end

return {
    ListItem = LibbyListItem,
}
