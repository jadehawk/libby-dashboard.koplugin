local Blitbuffer = require("ffi/blitbuffer")
local DiagnosticLog = require("diagnostic_log")
local Dpad = require("libby_dpad")
local CatalogLayout = require("libby_catalog_layout")
local Button = require("ui/widget/button")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local TopContainer = require("ui/widget/container/topcontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local NetworkMgr = require("ui/network/manager")
local RenderImage = require("ui/renderimage")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local util = require("util")
local _ = require("gettext")

local Screen = Device.screen
local source_path = debug.getinfo(1, "S").source:gsub("^@", "")
local plugin_root = source_path:match("^(.*)[/\\]libby_catalog%.lua$")
local GLOBE_ICON_PATH = plugin_root and (plugin_root .. "/dependencies/icons/globe.svg") or nil
local GRID_ICON_PATH = plugin_root and (plugin_root .. "/dependencies/icons/view-grid.svg") or nil
local LIST_ICON_PATH = plugin_root and (plugin_root .. "/dependencies/icons/view-list.svg") or nil
local SETTINGS_ICON_PATH = plugin_root and (plugin_root .. "/dependencies/icons/settings.svg") or nil
local REFRESH_ICON_PATH = plugin_root and (plugin_root .. "/dependencies/icons/refresh.svg") or nil
local CLOSE_ICON_PATH = plugin_root and (plugin_root .. "/dependencies/icons/close.svg") or nil
local HOLDS_ICON_PATH = plugin_root and (plugin_root .. "/dependencies/icons/holds.svg") or nil
local SWAP_ICON_PATH = plugin_root and (plugin_root .. "/dependencies/icons/swap.svg") or nil
local EXPIRES_TODAY_COLOR = Blitbuffer.colorFromName("red")

local TopFirstOverlapGroup = OverlapGroup:extend{}

function TopFirstOverlapGroup:propagateEvent(event)
    for index = #self, 1, -1 do
        local widget = self[index]
        if widget:handleEvent(event) then return true end
    end
    return false
end

local LibbyCatalog = InputContainer:extend{
    name = "libby_catalog",
    covers_fullscreen = true,
}

local function tappableFrame(text, width, height, selected, callback, font_size)
    local fg = selected and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
    local bg = selected and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE
    local label = TextWidget:new{
        text = text,
        face = Font:getFace("cfont", font_size or 13),
        bold = selected,
        fgcolor = fg,
        max_width = math.max(1, width - 2 * Screen:scaleBySize(8)),
    }
    local frame = FrameContainer:new{
        width = width,
        height = height,
        margin = 0,
        padding = 0,
        padding_left = Screen:scaleBySize(8),
        padding_right = Screen:scaleBySize(8),
        bordersize = Size.border.thin,
        color = Blitbuffer.COLOR_BLACK,
        background = bg,
        radius = 0,
        CenterContainer:new{ dimen = Geom:new{ w = width, h = height }, label },
    }
    local item = InputContainer:new{ dimen = Geom:new{ w = width, h = height }, frame }
    item.ges_events = { TapSelect = { GestureRange:new{ ges = "tap", range = item.dimen } } }
    item.onTapSelect = function()
        if callback then callback() end
        return true
    end
    return item
end

local function actionButton(text, width, height, available, callback, focused)
    local focus_border = math.max(Size.border.default, Screen:scaleBySize(3))
    local bg = focused and Blitbuffer.COLOR_WHITE or (available and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_LIGHT_GRAY)
    local fg = focused and Blitbuffer.COLOR_BLACK or (available and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_DARK_GRAY)
    local label = TextWidget:new{
        text = text,
        face = Font:getFace("cfont", 15),
        bold = true,
        fgcolor = fg,
        max_width = math.max(1, width - 2 * Screen:scaleBySize(10)),
    }
    local frame = FrameContainer:new{
        width = width,
        height = height,
        margin = 0,
        padding = 0,
        bordersize = focused and focus_border or 0,
        color = Blitbuffer.COLOR_BLACK,
        background = bg,
        radius = Size.radius.button,
        CenterContainer:new{ dimen = Geom:new{ w = width, h = height }, label },
    }
    local item = InputContainer:new{ dimen = Geom:new{ w = width, h = height }, frame }
    item.ges_events = { TapSelect = { GestureRange:new{ ges = "tap", range = item.dimen } } }
    item.onTapSelect = function()
        if callback then callback() end
        return true
    end
    return item
end

local function filterButton(text, width, height, selected, callback)
    local fg = selected and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
    local bg = selected and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE
    local label = TextWidget:new{
        text = text,
        face = Font:getFace("cfont", 13),
        bold = true,
        fgcolor = fg,
        max_width = math.max(1, width - 2 * Screen:scaleBySize(5)),
    }
    local frame = FrameContainer:new{
        width = width,
        height = height,
        margin = 0,
        padding = 0,
        bordersize = Size.border.thin,
        color = Blitbuffer.COLOR_BLACK,
        background = bg,
        radius = Size.radius.button,
        CenterContainer:new{ dimen = Geom:new{ w = width, h = height }, label },
    }
    local item = InputContainer:new{ dimen = Geom:new{ w = width, h = height }, frame }
    item.ges_events = { TapSelect = { GestureRange:new{ ges = "tap", range = item.dimen } } }
    item.onTapSelect = function()
        if callback then callback() end
        return true
    end
    return item
end

local function iconTap(icon, width, height, callback, icon_size, tap_extend_left, focused)
    local size = icon_size or math.floor(height * 0.62)
    local icon_widget
    if type(icon) == "string" and (icon:find("/", 1, true) or icon:find("\\", 1, true)) then
        icon_widget = IconWidget:new{ file = icon, width = size, height = size }
    else
        icon_widget = IconWidget:new{ icon = icon, width = size, height = size }
    end
    local focus_border = math.max(Size.border.default, Screen:scaleBySize(3))
    local focus_inset = math.max(1, Size.border.thin)
    local inner_w = math.max(1, width - 2 * focus_inset)
    local inner_h = math.max(1, height - 2 * focus_inset)
    local frame = FrameContainer:new{
        width = inner_w,
        height = inner_h,
        margin = 0,
        padding = 0,
        bordersize = focused and focus_border or 0,
        color = Blitbuffer.COLOR_BLACK,
        radius = 0,
        CenterContainer:new{
            dimen = Geom:new{ w = inner_w, h = inner_h },
            icon_widget,
        },
    }
    local item = InputContainer:new{
        dimen = Geom:new{ w = width, h = height },
        CenterContainer:new{ dimen = Geom:new{ w = width, h = height }, frame },
    }
    local tap_range = tap_extend_left and Geom:new{ x = -width, y = 0, w = width * 2, h = height } or item.dimen
    item.ges_events = { TapSelect = { GestureRange:new{ ges = "tap", range = tap_range } } }
    item.onTapSelect = function()
        if callback then callback() end
        return true
    end
    return item
end

local function filterIconTap(icon, width, height, selected, callback, icon_size, focused)
    local size = icon_size or math.floor(height * 0.62)
    local icon_widget
    if type(icon) == "string" and (icon:find("/", 1, true) or icon:find("\\", 1, true)) then
        icon_widget = IconWidget:new{ file = icon, width = size, height = size }
    else
        icon_widget = IconWidget:new{ icon = icon, width = size, height = size }
    end
    local focus_border = math.max(Size.border.default, Screen:scaleBySize(3))
    local focus_inset = math.max(1, Size.border.thin)
    local inner_w = math.max(1, width - 2 * focus_inset)
    local inner_h = math.max(1, height - 2 * focus_inset)
    local frame = FrameContainer:new{
        width = inner_w,
        height = inner_h,
        margin = 0,
        padding = 0,
        bordersize = focused and focus_border or 0,
        color = Blitbuffer.COLOR_BLACK,
        invert = selected == true,
        CenterContainer:new{
            dimen = Geom:new{ w = inner_w, h = inner_h },
            icon_widget,
        },
    }
    local item = InputContainer:new{
        dimen = Geom:new{ w = width, h = height },
        CenterContainer:new{ dimen = Geom:new{ w = width, h = height }, frame },
    }
    item.ges_events = { TapSelect = { GestureRange:new{ ges = "tap", range = item.dimen } } }
    item.onTapSelect = function()
        if callback then callback() end
        return true
    end
    return item
end

local function tappableWidget(widget, width, height, callback)
    local item = InputContainer:new{
        dimen = Geom:new{ w = width, h = height },
        widget,
    }
    item.ges_events = { TapSelect = { GestureRange:new{ ges = "tap", range = item.dimen } } }
    item.onTapSelect = function()
        if callback then callback() end
        return true
    end
    return item
end

local function wifiStatusWidget(width, height)
    local online = type(NetworkMgr.isOnline) ~= "function" or NetworkMgr:isOnline()

    local label = online and _("ONLINE") or _("OFFLINE")
    local icon_size = math.min(Screen:scaleBySize(24), math.max(1, height - Screen:scaleBySize(14)))
    local group = HorizontalGroup:new{ align = "center" }
    if GLOBE_ICON_PATH then
        table.insert(group, IconWidget:new{ file = GLOBE_ICON_PATH, width = icon_size, height = icon_size })
    else
        table.insert(group, IconWidget:new{ icon = "wifi", width = icon_size, height = icon_size })
    end
    table.insert(group, HorizontalSpan:new{ width = Screen:scaleBySize(3) })
    table.insert(group, TextWidget:new{
        text = label,
        face = Font:getFace("cfont", 11),
        bold = online,
    })
    return CenterContainer:new{ dimen = Geom:new{ w = width, h = height }, group }
end

local function hamburgerTap(width, height, callback)
    local Widget = require("ui/widget/widget")
    local art_size = math.min(Screen:scaleBySize(32), math.max(1, height - Screen:scaleBySize(8)))
    local bar_t = math.max(1, math.floor(art_size / 14))
    local span = math.floor(art_size * 0.62)
    local gap = math.max(1, math.floor((span - 3 * bar_t) / 2))
    span = 3 * bar_t + 2 * gap
    local BarsWidget = Widget:extend{}
    function BarsWidget:getSize() return Geom:new{ w = art_size, h = art_size } end
    function BarsWidget:paintTo(bb, x, y)
        local top = y + math.floor((art_size - span) / 2)
        for i = 0, 2 do
            bb:paintRect(x, top + i * (bar_t + gap), art_size, bar_t, Blitbuffer.COLOR_BLACK)
        end
    end
    local item = InputContainer:new{
        dimen = Geom:new{ w = width, h = height },
        CenterContainer:new{ dimen = Geom:new{ w = width, h = height }, BarsWidget:new{} },
    }
    local tap_range = Geom:new{ x = 0, y = 0, w = width * 2, h = height }
    item.ges_events = { TapSelect = { GestureRange:new{ ges = "tap", range = tap_range } } }
    item.onTapSelect = function()
        if callback then callback() end
        return true
    end
    return item
end

local function refreshAgeText(snapshot, refresh_state)
    if refresh_state == "refreshing" then return _("Refreshing…") end
    local updated = snapshot and tonumber(snapshot.updated_at)
    if not updated then return _("Cached") end
    local age = math.max(0, os.time() - updated)
    if age < 60 then return _("Just now") end
    if age < 3600 then return string.format(_("%dm ago"), math.floor(age / 60)) end
    if age < 86400 then return string.format(_("%dh ago"), math.floor(age / 3600)) end
    return string.format(_("%dd ago"), math.floor(age / 86400))
end

local CoverCard = InputContainer:extend{
    loan = nil,
    dimen = nil,
    selected = false,
    focused = false,
    cover_path = nil,
    callback = nil,
}

local function safeText(value, max_len)
    local text = tostring(value or ""):gsub("[%z\1-\31\127]", " "):gsub("%s+", " ")
    if #text <= (max_len or 96) then return text end
    return text:sub(1, math.max(1, (max_len or 96) - 3)) .. "..."
end

local function measureHeaderText(text, face)
    local probe = TextWidget:new{ text = text, face = face, bold = true }
    return probe:getSize().w
end

local function fitExpandedHeaderText(library_name, loan_count, max_width, refreshing)
    local name = tostring(library_name or "")
    local suffix = " (" .. tostring(loan_count or 0) .. ")"
    if refreshing then suffix = suffix .. " — " .. _("Refreshing…") end
    for _, size in ipairs({ 15, 14, 13 }) do
        local face = Font:getFace("cfont", size)
        local text = name .. suffix
        if measureHeaderText(text, face) <= max_width then return text, face end
    end

    local face = Font:getFace("cfont", 13)
    local chars = util.splitToChars(name)
    local left = math.ceil(#chars / 2)
    local right = #chars - left
    while left > 0 or right > 0 do
        local right_start = #chars - right + 1
        local left_text = left > 0 and table.concat(chars, "", 1, left) or ""
        local right_text = right > 0 and table.concat(chars, "", right_start, #chars) or ""
        local candidate = left_text .. "…" .. right_text .. suffix
        if measureHeaderText(candidate, face) <= max_width then return candidate, face end
        if left >= right and left > 0 then
            left = left - 1
        elseif right > 0 then
            right = right - 1
        else
            break
        end
    end
    return "…" .. suffix, face
end

local function holdWaitText(days)
    days = tonumber(days)
    if not days or days <= 0 then return nil end
    if days == 1 then return _("1 day") end
    if days < 14 then return string.format(_("%d days"), math.floor(days + 0.5)) end
    if days < 60 then return string.format(_("~%d weeks"), math.max(1, math.floor(days / 7 + 0.5))) end
    return string.format(_("~%d months"), math.max(1, math.floor(days / 30 + 0.5)))
end

local function holdDetailedStatus(loan)
    if loan and loan.suspension_flag == true then return _("Suspended") end
    if loan and (loan.is_available == true or (tonumber(loan.lucky_day_available_copies) or 0) > 0) then
        return _("Ready to borrow")
    end
    return _("On Hold")
end

local function holdBorrowable(loan)
    return loan ~= nil and (loan.is_available == true or (tonumber(loan.lucky_day_available_copies) or 0) > 0)
end

local function holdCompactStatus(loan)
    if not loan then return _("On Hold") end
    if loan.suspension_flag == true then return _("Suspended") end
    if loan.is_available == true or (tonumber(loan.lucky_day_available_copies) or 0) > 0 then
        return _("Ready to borrow")
    end
    local position = tonumber(loan.hold_list_position)
    local wait = holdWaitText(loan.estimated_wait_days)
    if position and position > 0 and wait then
        return string.format(_("#%d in line · %s"), position, wait)
    end
    if position and position > 0 then return string.format(_("#%d in line"), position) end
    if wait then return string.format(_("%s wait"), wait) end
    return _("On Hold")
end

local function loanTimeText(loan)
    if loan and loan.on_hold == true then return holdCompactStatus(loan) end
    if loan and loan.extended_loan == true then return _("Extended Loan") end
    local days = loan and tonumber(loan.days_remaining)
    if days == nil then return _("N/A") end
    if days <= 0 then return _("Expires Today") end
    if days == 1 then return _("1 day left") end
    return string.format(_("%d days left"), days)
end

local function loanTimeColor(loan)
    local days = loan and tonumber(loan.days_remaining)
    return days ~= nil and days <= 0 and EXPIRES_TODAY_COLOR or Blitbuffer.COLOR_BLACK
end

-- TextWidget's colorblitFrom() path intentionally coerces RGB colors to grayscale.
-- Use TextBoxWidget for RGB foreground colors so "Expires Today" stays red on color screens.
local function colorAwareTextWidget(args)
    local fgcolor = args.fgcolor or Blitbuffer.COLOR_BLACK
    if not args.force_textbox and Blitbuffer.isColor8(fgcolor) then
        return TextWidget:new(args)
    end
    return TextBoxWidget:new{
        text = args.text,
        face = args.face,
        bold = args.bold,
        fgcolor = fgcolor,
        bgcolor = Blitbuffer.COLOR_WHITE,
        width = math.max(1, args.max_width or args.width or Screen:scaleBySize(120)),
        height = args.forced_height or args.height,
        alignment = args.alignment or "left",
        line_height = 0,
        use_xtext = true,
    }
end

local function alignedColorValueRow(label_text, value_text, face, width, value_color, bold)
    local measure = TextWidget:new{ text = label_text, face = face }
    local label_w = measure:getSize().w
    local row_h = measure:getSize().h
    if measure.free then measure:free() end
    local value_w = math.max(1, width - label_w)
    return HorizontalGroup:new{
        align = "center",
        colorAwareTextWidget{
            text = label_text,
            face = face,
            fgcolor = Blitbuffer.COLOR_BLACK,
            max_width = label_w,
            forced_height = row_h,
            force_textbox = true,
        },
        colorAwareTextWidget{
            text = value_text,
            face = face,
            fgcolor = value_color,
            bold = bold,
            max_width = value_w,
            forced_height = row_h,
            force_textbox = true,
        },
    }
end

local function outlinedLabel(text, width, height, focused)
    local label = TextWidget:new{
        text = text,
        face = Font:getFace("cfont", 15),
        bold = true,
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        max_width = math.max(1, width - 2 * Screen:scaleBySize(10)),
    }
    return FrameContainer:new{
        width = width,
        height = height,
        margin = 0,
        padding = 0,
        bordersize = focused and math.max(Size.border.default, Screen:scaleBySize(3)) or Size.border.thin,
        color = Blitbuffer.COLOR_BLACK,
        background = Blitbuffer.COLOR_WHITE,
        radius = Size.radius.button,
        CenterContainer:new{ dimen = Geom:new{ w = width, h = height }, label },
    }
end

local function downloadFormat(loan)
    return loan and (loan.download_format or loan.adobe_format) or nil
end

local function mediaLabel(loan)
    if loan.media_type == "audiobook" then return _("Audiobook") end
    if loan.media_type == "magazine" then return _("Magazine") end
    if loan.media_type == "comic" then return _("Manga/Comic") end
    if downloadFormat(loan) and downloadFormat(loan):find("pdf", 1, true) then return _("PDF") end
    if downloadFormat(loan) then return _("EPUB") end
    if loan.non_adobe_format_label then return loan.non_adobe_format_label end
    return _("Unsupported")
end

local function loanKey(loan)
    return tostring(loan and (loan.id or loan.title) or "")
end

local function fakeCover(loan, width, height)
    local text_w = math.max(1, width - 2 * Size.padding.small)
    local content = VerticalGroup:new{ align = "center" }
    table.insert(content, TextBoxWidget:new{
        text = safeText(loan.title or _("Untitled"), 56),
        width = text_w,
        alignment = "center",
        bold = true,
        face = Font:getFace("smallinfofont", 16),
        height_overflow_show_ellipsis = true,
    })
    if loan.author then
        table.insert(content, VerticalSpan:new{ width = Size.span.vertical_default })
        table.insert(content, TextBoxWidget:new{
            text = safeText(loan.author, 40),
            width = text_w,
            alignment = "center",
            face = Font:getFace("x_smallinfofont", 13),
            height_overflow_show_ellipsis = true,
        })
    end
    return FrameContainer:new{
        width = width,
        height = height,
        margin = 0,
        padding = Size.padding.small,
        bordersize = Size.border.thin,
        background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{
            dimen = Geom:new{ w = text_w, h = math.max(1, height - 2 * Size.padding.small) },
            content,
        },
    }
end

local function coverWidget(loan, width, height, path, selected, focused)
    local focus_border = math.max(Size.border.default, Screen:scaleBySize(3))
    local border = focused and focus_border or (selected and Size.border.default or Size.border.thin)
    if path then
        local inner_w = math.max(1, width - 2 * border)
        local inner_h = math.max(1, height - 2 * border)
        local ok, scaled = pcall(function()
            return RenderImage:renderImageFile(path, false, inner_w, inner_h)
        end)
        if ok and scaled then
            return FrameContainer:new{
                width = width,
                height = height,
                margin = 0,
                padding = 0,
                bordersize = border,
                background = Blitbuffer.COLOR_WHITE,
                ImageWidget:new{
                    image = scaled,
                    image_disposable = true,
                    scale_factor = 1,
                },
            }
        end
    end
    local cover = fakeCover(loan, width, height)
    if focused then
        cover.bordersize = focus_border
    elseif selected then
        cover.bordersize = Size.border.default
    end
    return cover
end

function CoverCard:init()
    self.ges_events = {
        TapSelect = { GestureRange:new{ ges = "tap", range = self.dimen } },
    }
    local loan = self.loan or {}
    self[1] = coverWidget(loan, self.dimen.w, self.dimen.h, self.cover_path, self.selected, self.focused)
end

function CoverCard:onTapSelect()
    if self.callback then self.callback(self.loan) end
    return true
end

local function cardId(card)
    return card and (card.id or card.cardId)
end

local function rawCardName(card)
    return tostring(card and (card.name or card.libraryName or card.id) or _("Library"))
end

local function cardName(card)
    return safeText(rawCardName(card), 30)
end

function LibbyCatalog:init()
    self.settings = self.settings or {}
    self.snapshot = self.snapshot or {}
    self.width = Screen:getWidth()
    self.height = Screen:getHeight()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self.selected_card_id = self.settings.libby_selected_card_id or "__all__"
    self.selected_loan_id = self.settings.libby_selected_loan_id
    self.grid_columns = math.max(2, math.min(8, tonumber(self.settings.libby_shelf_columns) or 4))
    self.grid_rows = math.max(1, math.min(5, tonumber(self.settings.libby_shelf_rows) or 2))
    self.shelf_page = math.max(1, tonumber(self.settings.libby_shelf_page) or 1)
    self.expanded = false
    self.expanded_detail_visible = false
    self.expanded_holds_only = false
    self.expanded_view_mode = self.settings.libby_expanded_view_mode == "list" and "list" or "grid"
    self.expanded_grid_columns = math.max(2, math.min(8, tonumber(self.settings.libby_expanded_grid_columns) or 4))
    self.expanded_grid_rows = math.max(1, math.min(6, tonumber(self.settings.libby_expanded_grid_rows) or 3))
    self.expanded_grid_page = math.max(1, tonumber(self.settings.libby_expanded_grid_page) or 1)
    self.expanded_list_rows = math.max(4, math.min(12, tonumber(self.settings.libby_expanded_list_rows) or 7))
    self.expanded_list_page = math.max(1, tonumber(self.settings.libby_expanded_list_page) or 1)
    self.key_focus_active = false
    self.key_focus_region = nil
    self.key_focus_index = nil
    self.key_header_index = 1
    self.key_detail_action_index = 1
    self.ges_events = {
        SwipeShelfNext = { GestureRange:new{ ges = "swipe", range = self.dimen, direction = "west" } },
        SwipeShelfPrev = { GestureRange:new{ ges = "swipe", range = self.dimen, direction = "east" } },
    }
    self.key_events = {
        KeyUp = { { "Up" } },
        KeyDown = { { "Down" } },
        KeyLeft = { { "Left" } },
        KeyRight = { { "Right" } },
        KeyPress = { { "Press" }, { "Enter" } },
        KeyPrevPage = { { "PgBack" } },
        KeyNextPage = { { "PgFwd" } },
        KeyBack = { { "Esc" }, { "Back" } },
        KeyMenu = { { "Menu" } },
    }
    local groups = Device.input and Device.input.group or nil
    if groups then
        if groups.Up then table.insert(self.key_events.KeyUp, { groups.Up }) end
        if groups.Down then table.insert(self.key_events.KeyDown, { groups.Down }) end
        if groups.Left then table.insert(self.key_events.KeyLeft, { groups.Left }) end
        if groups.Right then table.insert(self.key_events.KeyRight, { groups.Right }) end
        if groups.Press then table.insert(self.key_events.KeyPress, { groups.Press }) end
        if groups.Enter then table.insert(self.key_events.KeyPress, { groups.Enter }) end
        if groups.PgBack then table.insert(self.key_events.KeyPrevPage, { groups.PgBack }) end
        if groups.PgFwd then table.insert(self.key_events.KeyNextPage, { groups.PgFwd }) end
        if groups.Back then table.insert(self.key_events.KeyBack, { groups.Back }) end
        if groups.Menu then table.insert(self.key_events.KeyMenu, { groups.Menu }) end
    end
    self:updateItems()
end

function LibbyCatalog:keyFocusPerPage()
    if self.expanded then
        if self.expanded_view_mode == "list" then return math.max(1, self.expanded_list_rows) end
        return math.max(1, self.expanded_grid_columns * self.expanded_grid_rows)
    end
    return math.max(1, self.grid_columns * self.grid_rows)
end

function LibbyCatalog:keyFocusColumns()
    if self.expanded and self.expanded_view_mode == "list" then return 1 end
    return self.expanded and self.expanded_grid_columns or self.grid_columns
end

function LibbyCatalog:activateKeyFocus()
    self.key_focus_active = true
    self.key_focus_region = "books"
    local loans = self:loansForSelectedCard()
    self.key_focus_index = Dpad.find_index(loans, self.selected_loan_id, loanKey)
    if self.expanded_detail_visible then self.key_detail_action_index = 1 end
    return self.key_focus_index ~= nil
end

function LibbyCatalog:focusedKeyLoan()
    if not self.key_focus_active or self.key_focus_region ~= "books" then return nil end
    local loans = self:loansForSelectedCard()
    local index = tonumber(self.key_focus_index)
    return index and loans[index] or nil
end

function LibbyCatalog:isKeyFocusedLoan(loan)
    local focused = self:focusedKeyLoan()
    return focused ~= nil and loanKey(focused) == loanKey(loan) and not self.expanded_detail_visible
end

function LibbyCatalog:syncKeyFocusPage()
    if not self.key_focus_index then return end
    local page = Dpad.page_for(self.key_focus_index, self:keyFocusPerPage())
    if self.expanded then
        if self.expanded_view_mode == "list" then
            self.expanded_list_page = page
            self.settings.libby_expanded_list_page = page
        else
            self.expanded_grid_page = page
            self.settings.libby_expanded_grid_page = page
        end
    else
        self.shelf_page = page
        self.settings.libby_shelf_page = page
    end
end

function LibbyCatalog:bookNote(loan)
    local note = self.book_note_callback and self.book_note_callback(loan) or nil
    if type(note) ~= "string" then return "" end
    return note
end

function LibbyCatalog:coverStatusText(loan)
    local downloaded_path = self.downloaded_path_callback and self.downloaded_path_callback(loan) or nil
    if type(downloaded_path) == "string" and downloaded_path ~= "" then return loanTimeText(loan) end
    if loan and loan.on_hold == true then return holdCompactStatus(loan) end
    if loan and loan.extended_loan == true then return loanTimeText(loan) end
    if not loan or loan.media_type == "audiobook" or loan.media_type == "magazine" or not downloadFormat(loan) then
        return _("Read on Libby")
    end
    return loanTimeText(loan)
end

function LibbyCatalog:keyDetailActions()
    local loan = self:selectedLoan()
    if not loan then return {} end
    local actions = {}
    local downloaded_path = self.downloaded_path_callback and self.downloaded_path_callback(loan) or nil
    local locally_available = type(downloaded_path) == "string" and downloaded_path ~= ""
    local network_ok = self.network_available_callback == nil or self.network_available_callback()
    local on_hold = loan.on_hold == true
    local extended = loan.extended_loan == true

    if on_hold then
        if holdBorrowable(loan) then
            table.insert(actions, network_ok and function()
                if self.borrow_hold_callback then self.borrow_hold_callback(loan) end
            end or false)
        end
        table.insert(actions, network_ok and function()
            if self.cancel_hold_callback then self.cancel_hold_callback(loan) end
        end or false)
    elseif locally_available then
        table.insert(actions, function()
            if self.open_callback then self.open_callback(downloaded_path) end
        end)
    elseif extended then
        table.insert(actions, false)
    elseif downloadFormat(loan) and loan.media_type ~= "audiobook" and loan.media_type ~= "magazine" then
        table.insert(actions, network_ok and function()
            if self.download_callback then self.download_callback(loan) end
        end or false)
    else
        table.insert(actions, false)
    end

    if self.return_enabled == true and not extended and not on_hold then
        table.insert(actions, network_ok and function()
            if self.return_callback then self.return_callback(loan) end
        end or false)
    elseif extended then
        table.insert(actions, function()
            if self.delete_callback then self.delete_callback(loan) end
        end)
    end

    -- Book Notes follow the title through Hold -> Borrowed -> Downloaded/Extended Loan.
    table.insert(actions, function()
        if self.edit_book_note_callback then self.edit_book_note_callback(loan) end
    end)
    table.insert(actions, function() self:hideExpandedDetail() end)
    return actions
end

function LibbyCatalog:isKeyDetailActionFocused(index)
    return self.key_focus_active and self.expanded_detail_visible
        and tonumber(self.key_detail_action_index or 1) == index
end

function LibbyCatalog:keyHeaderActions()
    if self.expanded then
        return {
            function() self:cycleExpandedLibraryScope() end,
            self.refresh_state ~= "refreshing" and self.refresh_callback
                and function() self.refresh_callback() end or false,
            function() self:toggleExpandedHolds() end,
            function() self:toggleExpandedView() end,
            function() self:closeExpanded() end,
        }
    end
    return {
        self.settings_callback and function() self.settings_callback() end or false,
        self.refresh_state ~= "refreshing" and self.refresh_callback
            and function() self.refresh_callback() end or false,
        function()
            if self.close_callback then self.close_callback() else UIManager:close(self) end
        end,
    }
end

function LibbyCatalog:isKeyHeaderActionFocused(index)
    return self.key_focus_active and not self.expanded_detail_visible
        and self.key_focus_region == "header"
        and tonumber(self.key_header_index or 1) == index
end

function LibbyCatalog:enterKeyHeaderFocus()
    self.key_focus_active = true
    self.key_focus_region = "header"
    local count = math.max(1, #self:keyHeaderActions())
    self.key_header_index = math.max(1, math.min(count, tonumber(self.key_header_index) or 1))
    self:updateItems()
    return true
end

function LibbyCatalog:moveKeyFocus(direction)
    if not self.key_focus_active then self:activateKeyFocus() end
    if self.expanded_detail_visible then
        local count = #self:keyDetailActions()
        if count > 0 then
            local delta = (direction == "right" or direction == "down") and 1 or -1
            self.key_detail_action_index = ((tonumber(self.key_detail_action_index) or 1) - 1 + delta) % count + 1
            self:updateItems()
        end
        return true
    end

    if self.key_focus_region == "header" then
        local count = math.max(1, #self:keyHeaderActions())
        if direction == "down" then
            self.key_focus_region = "books"
            local loans = self:loansForSelectedCard()
            self.key_focus_index = Dpad.find_index(loans, self.selected_loan_id, loanKey)
            self:syncKeyFocusPage()
        elseif direction == "left" or direction == "right" then
            local delta = direction == "right" and 1 or -1
            self.key_header_index = ((tonumber(self.key_header_index) or 1) - 1 + delta) % count + 1
        end
        self:updateItems()
        return true
    end

    local loans = self:loansForSelectedCard()
    if #loans == 0 then return self:enterKeyHeaderFocus() end
    if not self.key_focus_index then self:activateKeyFocus() end
    local index = tonumber(self.key_focus_index)
    local per_page = self:keyFocusPerPage()
    local index_on_page = index and (((index - 1) % per_page) + 1) or 1
    if direction == "up" and index_on_page <= self:keyFocusColumns() then
        return self:enterKeyHeaderFocus()
    end
    self.key_focus_index = Dpad.move_grid(
        self.key_focus_index, direction, self:keyFocusColumns(), #loans
    )
    self:syncKeyFocusPage()
    self:updateItems()
    return true
end

function LibbyCatalog:onKeyUp() return self:moveKeyFocus("up") end
function LibbyCatalog:onKeyDown() return self:moveKeyFocus("down") end
function LibbyCatalog:onKeyLeft() return self:moveKeyFocus("left") end
function LibbyCatalog:onKeyRight() return self:moveKeyFocus("right") end

function LibbyCatalog:changeKeyPage(delta)
    if self.expanded_detail_visible then return true end
    if not self.key_focus_active then self:activateKeyFocus() end
    local loans = self:loansForSelectedCard()
    if #loans == 0 then return true end
    local per_page = self:keyFocusPerPage()
    local current = self.expanded and self:expandedPage() or self.shelf_page
    local page_count = math.max(1, math.ceil(#loans / per_page))
    local next_page = math.max(1, math.min(page_count, current + delta))
    self.key_focus_index = Dpad.first_index_for_page(next_page, per_page, #loans)
    self:syncKeyFocusPage()
    self:updateItems()
    return true
end

function LibbyCatalog:onKeyPrevPage() return self:changeKeyPage(-1) end
function LibbyCatalog:onKeyNextPage() return self:changeKeyPage(1) end

function LibbyCatalog:onKeyPress()
    if not self.key_focus_active then self:activateKeyFocus() end
    if self.expanded_detail_visible then
        local actions = self:keyDetailActions()
        local action = actions[tonumber(self.key_detail_action_index) or 1]
        if type(action) == "function" then action() end
        return true
    end
    if self.key_focus_region == "header" then
        local actions = self:keyHeaderActions()
        local action = actions[tonumber(self.key_header_index) or 1]
        if type(action) == "function" then action() end
        return true
    end

    local loan = self:focusedKeyLoan() or self:selectedLoan()
    if loan then
        self.expanded = true
        self.expanded_detail_visible = true
        self.selected_loan_id = loanKey(loan)
        self.key_detail_action_index = 1
        self:persistSelection()
        self:updateItems()
    end
    return true
end

function LibbyCatalog:onKeyBack()
    if self.expanded_detail_visible then
        self.expanded_detail_visible = false
        self.key_focus_active = true
        self:activateKeyFocus()
        self:updateItems()
    elseif self.expanded then
        self.expanded = false
        self.key_focus_active = true
        self:activateKeyFocus()
        self:updateItems()
    elseif self.close_callback then
        self.close_callback()
    else
        UIManager:close(self)
    end
    return true
end

function LibbyCatalog:onKeyMenu()
    if self.settings_callback then self.settings_callback() end
    return true
end

function LibbyCatalog:loansForSelectedCard()
    local loans = type(self.snapshot.loans) == "table" and self.snapshot.loans or {}
    if self.expanded and self.expanded_holds_only then
        local holds = {}
        for _, loan in ipairs(loans) do
            if loan.on_hold == true then table.insert(holds, loan) end
        end
        loans = holds
    end
    if self.selected_card_id == "__all__" then return loans end
    local filtered = {}
    for _, loan in ipairs(loans) do
        if tostring(loan.card_id or "") == tostring(self.selected_card_id or "") then
            table.insert(filtered, loan)
        end
    end
    return filtered
end

function LibbyCatalog:selectedLibraryInfo()
    local loans = self:loansForSelectedCard()
    if self.selected_card_id == "__all__" then
        return _("All Libraries"), #loans
    end
    for _, card in ipairs(type(self.snapshot.cards) == "table" and self.snapshot.cards or {}) do
        if tostring(cardId(card) or "") == tostring(self.selected_card_id or "") then
            return rawCardName(card), #loans
        end
    end
    local fallback = loans[1] and loans[1].library or _("Library")
    return tostring(fallback), #loans
end

function LibbyCatalog:cycleExpandedLibraryScope()
    local cards = type(self.snapshot.cards) == "table" and self.snapshot.cards or {}
    local scopes = {}
    for _, card in ipairs(cards) do
        local id = cardId(card)
        if id ~= nil and tostring(id) ~= "" then table.insert(scopes, tostring(id)) end
    end
    table.insert(scopes, "__all__")

    local current = tostring(self.selected_card_id or "__all__")
    local current_index
    for index, id in ipairs(scopes) do
        if tostring(id) == current then
            current_index = index
            break
        end
    end
    local next_index = current_index and (current_index % #scopes + 1) or 1
    self:selectCard(scopes[next_index], true)
end

function LibbyCatalog:expandedPageCount()
    local per_page = self.expanded_view_mode == "list"
        and self.expanded_list_rows
        or math.max(1, self.expanded_grid_columns * self.expanded_grid_rows)
    return math.max(1, math.ceil(#self:loansForSelectedCard() / math.max(1, per_page)))
end

function LibbyCatalog:expandedPage()
    return self.expanded_view_mode == "list" and self.expanded_list_page or self.expanded_grid_page
end

function LibbyCatalog:setExpandedPage(page)
    local count = self:expandedPageCount()
    local next_page = math.max(1, math.min(count, tonumber(page) or 1))
    if self.expanded_view_mode == "list" then
        self.expanded_list_page = next_page
        self.settings.libby_expanded_list_page = next_page
    else
        self.expanded_grid_page = next_page
        self.settings.libby_expanded_grid_page = next_page
    end
    if self.selection_changed_callback then self.selection_changed_callback() end
    self:updateItems()
end

function LibbyCatalog:openExpanded()
    self.key_focus_active = false
    self.key_focus_region = nil
    self.key_focus_index = nil
    self.expanded = true
    self.expanded_detail_visible = false
    self:updateItems()
end

function LibbyCatalog:closeExpanded()
    self.expanded = false
    self.expanded_detail_visible = false
    if self.key_focus_active and self.key_focus_region == "header" then
        -- Keep D-pad focus on the normal dashboard Close icon after leaving expanded view.
        self.key_header_index = 3
    end
    self:updateItems()
end

function LibbyCatalog:toggleExpandedView()
    self.expanded_view_mode = self.expanded_view_mode == "grid" and "list" or "grid"
    self.settings.libby_expanded_view_mode = self.expanded_view_mode
    self.expanded_detail_visible = false
    if self.selection_changed_callback then self.selection_changed_callback() end
    self:updateItems()
end

function LibbyCatalog:toggleExpandedHolds()
    self.expanded_holds_only = not self.expanded_holds_only
    self.expanded_detail_visible = false
    self.selected_loan_id = nil
    self.expanded_grid_page = 1
    self.expanded_list_page = 1
    self.settings.libby_expanded_grid_page = 1
    self.settings.libby_expanded_list_page = 1
    if self.selection_changed_callback then self.selection_changed_callback() end
    self:updateItems()
end

function LibbyCatalog:showExpandedDetail(loan)
    self.key_focus_active = false
    self.key_focus_index = nil
    self.selected_loan_id = loanKey(loan)
    self.expanded_detail_visible = true
    self:persistSelection()
    self:updateItems()
end

function LibbyCatalog:hideExpandedDetail()
    self.expanded_detail_visible = false
    self:updateItems()
end

function LibbyCatalog:setExpandedLayout(columns, rows, list_rows)
    self.expanded_grid_columns = math.max(2, math.min(8, tonumber(columns) or 4))
    self.expanded_grid_rows = math.max(1, math.min(6, tonumber(rows) or 3))
    self.expanded_list_rows = math.max(4, math.min(12, tonumber(list_rows) or 7))
    self.settings.libby_expanded_grid_columns = self.expanded_grid_columns
    self.settings.libby_expanded_grid_rows = self.expanded_grid_rows
    self.settings.libby_expanded_list_rows = self.expanded_list_rows
    local loan_count = #self:loansForSelectedCard()
    local grid_pages = math.max(1, math.ceil(loan_count / math.max(1, self.expanded_grid_columns * self.expanded_grid_rows)))
    local list_pages = math.max(1, math.ceil(loan_count / math.max(1, self.expanded_list_rows)))
    self.expanded_grid_page = math.min(self.expanded_grid_page, grid_pages)
    self.expanded_list_page = math.min(self.expanded_list_page, list_pages)
    self.settings.libby_expanded_grid_page = self.expanded_grid_page
    self.settings.libby_expanded_list_page = self.expanded_list_page
    self:updateItems()
end

function LibbyCatalog:selectedLoan()
    local loans = self:loansForSelectedCard()
    if #loans == 0 then return nil end
    for _, loan in ipairs(loans) do
        if loanKey(loan) == tostring(self.selected_loan_id or "") then return loan end
    end
    self.selected_loan_id = loanKey(loans[1])
    return loans[1]
end

function LibbyCatalog:persistSelection()
    self.settings.libby_selected_card_id = self.selected_card_id
    self.settings.libby_selected_loan_id = self.selected_loan_id
    if self.selection_changed_callback then
        self.selection_changed_callback(self.selected_card_id, self.selected_loan_id)
    end
end

function LibbyCatalog:selectLoan(loan)
    self.key_focus_active = false
    self.key_focus_index = nil
    self.selected_loan_id = loanKey(loan)
    self:persistSelection()
    self:updateItems()
end

function LibbyCatalog:selectCard(id, preserve_header_focus)
    if preserve_header_focus ~= true then
        self.key_focus_active = false
        self.key_focus_region = nil
        self.key_focus_index = nil
    else
        self.key_focus_active = true
        self.key_focus_region = "header"
    end
    self.selected_card_id = id or "__all__"
    self.selected_loan_id = nil
    self.shelf_page = 1
    self.settings.libby_shelf_page = 1
    self.expanded_grid_page = 1
    self.expanded_list_page = 1
    self.settings.libby_expanded_grid_page = 1
    self.settings.libby_expanded_list_page = 1
    self:persistSelection()
    self:updateItems()
end

function LibbyCatalog:pageCount()
    local per_page = math.max(1, self.grid_columns * self.grid_rows)
    return math.max(1, math.ceil(#self:loansForSelectedCard() / per_page))
end

function LibbyCatalog:gotoShelfPage(page)
    local count = self:pageCount()
    local next_page = math.max(1, math.min(count, tonumber(page) or 1))
    if next_page == self.shelf_page then return false end
    self.shelf_page = next_page
    self.settings.libby_shelf_page = next_page
    local loans = self:loansForSelectedCard()
    local first_index = (next_page - 1) * math.max(1, self.grid_columns * self.grid_rows) + 1
    if loans[first_index] then
        self.selected_loan_id = loanKey(loans[first_index])
        self.settings.libby_selected_loan_id = self.selected_loan_id
    end
    if self.selection_changed_callback then self.selection_changed_callback() end
    self:updateItems()
    return true
end

function LibbyCatalog:onSwipeShelfNext()
    if self.expanded and not self.expanded_detail_visible then
        self:setExpandedPage(self:expandedPage() + 1)
    else
        self:gotoShelfPage(self.shelf_page + 1)
    end
    return true
end

function LibbyCatalog:onSwipeShelfPrev()
    if self.expanded and not self.expanded_detail_visible then
        self:setExpandedPage(self:expandedPage() - 1)
    else
        self:gotoShelfPage(self.shelf_page - 1)
    end
    return true
end

function LibbyCatalog:setShelfLayout(columns, rows)
    self.grid_columns = math.max(2, math.min(8, tonumber(columns) or 4))
    self.grid_rows = math.max(1, math.min(5, tonumber(rows) or 2))
    self.shelf_page = math.min(self.shelf_page, self:pageCount())
    self.settings.libby_shelf_columns = self.grid_columns
    self.settings.libby_shelf_rows = self.grid_rows
    self.settings.libby_shelf_page = self.shelf_page
    self:updateItems()
end

function LibbyCatalog:heroWidget(width, height)
    local loan = self:selectedLoan()
    if not loan then
        return CenterContainer:new{
            dimen = Geom:new{ w = width, h = height },
            TextWidget:new{ text = _("No borrowed or held titles in this library."), face = Font:getFace("infofont") },
        }
    end

    local pad = Size.padding.default
    local text_inset = Screen:scaleBySize(10)
    local cover_h = math.max(Screen:scaleBySize(90), height - 2 * pad)
    local cover_w = math.floor(cover_h * 0.66)
    local path = self.cover_path_callback and self.cover_path_callback(loan) or nil
    local text_w = math.max(1, width - cover_w - 4 * pad - text_inset)
    local hero_ratio = height / math.max(1, width)
    local font_step = hero_ratio >= 0.58 and 3 or (hero_ratio >= 0.50 and 2 or 0)
    local title_face = Font:getFace("cfont", 22 + font_step)
    local metadata_face = Font:getFace("smallinfofont", 17 + font_step)
    local info_top = VerticalGroup:new{ align = "left" }
    table.insert(info_top, TextWidget:new{
        text = safeText(loan.title or _("Untitled"), 120),
        bold = true,
        face = title_face,
        max_width = text_w,
    })

    local metadata_rows = {
        { label = _("Author: "), value = safeText(loan.author or _("N/A"), 80) },
        { label = _("Series: "), value = safeText(loan.series or _("N/A"), 80) },
        { label = _("Series Index: "), value = safeText(loan.series_index ~= nil and tostring(loan.series_index) or _("N/A"), 40) },
        { label = _("Format: "), value = mediaLabel(loan) },
        { label = _("Library: "), value = safeText(loan.library or _("N/A"), 100) },
        { label = (loan.extended_loan == true or loan.on_hold == true) and _("Status: ") or _("Expires On: "), value = loanTimeText(loan), fgcolor = loanTimeColor(loan) },
    }
    for _, row in ipairs(metadata_rows) do
        if row.fgcolor then
            table.insert(info_top, alignedColorValueRow(
                row.label, row.value, metadata_face, text_w, row.fgcolor, true
            ))
        else
            local label = TextWidget:new{
                text = row.label,
                face = metadata_face,
            }
            local value_w = math.max(1, text_w - label:getSize().w)
            local row_h = math.max(1, label:getSize().h - Screen:scaleBySize(4))
            label.forced_height = row_h
            table.insert(info_top, HorizontalGroup:new{
                align = "center",
                label,
                colorAwareTextWidget{
                    text = row.value,
                    fgcolor = Blitbuffer.COLOR_BLACK,
                    bold = true,
                    face = metadata_face,
                    max_width = value_w,
                    forced_height = row_h,
                },
            })
        end
    end

    local action_text
    local downloadable = downloadFormat(loan) ~= nil
    local downloaded_path = self.downloaded_path_callback and self.downloaded_path_callback(loan) or nil
    local locally_available = type(downloaded_path) == "string" and downloaded_path ~= ""
    local network_ok = self.network_available_callback == nil or self.network_available_callback()
    local extended = loan.extended_loan == true
    local on_hold = loan.on_hold == true
    local hold_borrowable = on_hold and holdBorrowable(loan)
    if on_hold then
        action_text = hold_borrowable and _("Borrow") or _("Cancel Hold")
        downloadable = false
    elseif locally_available then
        action_text = _("Open")
    elseif loan.media_type == "audiobook" or loan.media_type == "magazine" or not downloadFormat(loan) then
        action_text = _("Unsupported")
        downloadable = false
    else
        action_text = _("Download")
    end
    if extended and not locally_available then
        action_text = _("Unavailable")
        downloadable = false
    end

    local action_h = Screen:scaleBySize(34)
    local show_return = self.return_enabled == true and not extended and not on_hold
    local show_delete = extended
    local show_cancel_hold = on_hold and hold_borrowable
    local min_gap = Screen:scaleBySize(8)
    local button_w = (show_return or show_delete or show_cancel_hold)
        and math.max(1, math.floor((text_w - min_gap) / 2))
        or math.min(text_w, Screen:scaleBySize(150))
    local action
    if on_hold then
        action = actionButton(action_text, button_w, action_h, network_ok, function()
            if hold_borrowable then
                if self.borrow_hold_callback then self.borrow_hold_callback(loan) end
            elseif self.cancel_hold_callback then
                self.cancel_hold_callback(loan)
            end
        end)
    elseif locally_available then
        action = actionButton(action_text, button_w, action_h, true, function()
            if self.open_callback then self.open_callback(downloaded_path) end
        end)
    elseif downloadable then
        action = actionButton(action_text, button_w, action_h, network_ok, function()
            if self.download_callback then self.download_callback(loan) end
        end)
    else
        action = outlinedLabel(action_text, button_w, action_h)
    end

    local action_row = action
    if show_cancel_hold then
        local cancel_action = actionButton(_("Cancel Hold"), button_w, action_h, network_ok, function()
            if self.cancel_hold_callback then self.cancel_hold_callback(loan) end
        end)
        action_row = HorizontalGroup:new{
            align = "center",
            action,
            HorizontalSpan:new{ width = math.max(min_gap, text_w - 2 * button_w) },
            cancel_action,
        }
    elseif show_return then
        local return_action = actionButton(_("Return"), button_w, action_h, network_ok, function()
            if self.return_callback then self.return_callback(loan) end
        end)
        action_row = HorizontalGroup:new{
            align = "center",
            action,
            HorizontalSpan:new{ width = math.max(min_gap, text_w - 2 * button_w) },
            return_action,
        }
    elseif show_delete then
        local delete_action = actionButton(_("Delete"), button_w, action_h, true, function()
            if self.delete_callback then self.delete_callback(loan) end
        end)
        action_row = HorizontalGroup:new{
            align = "center",
            action,
            HorizontalSpan:new{ width = math.max(min_gap, text_w - 2 * button_w) },
            delete_action,
        }
    end
    local info = OverlapGroup:new{
        dimen = Geom:new{ w = text_w, h = cover_h },
        info_top,
        BottomContainer:new{
            dimen = Geom:new{ w = text_w, h = cover_h },
            LeftContainer:new{ dimen = Geom:new{ w = text_w, h = action_h }, action_row },
        },
    }

    return FrameContainer:new{
        width = width, height = height, margin = 0, padding = pad,
        bordersize = Size.border.thin, background = Blitbuffer.COLOR_WHITE,
        HorizontalGroup:new{
            align = "center",
            HorizontalSpan:new{ width = text_inset },
            info,
            HorizontalSpan:new{ width = 2 * pad },
            coverWidget(loan, cover_w, cover_h, path, true),
        },
    }
end

function LibbyCatalog:headerWidget(width, height)
    local button_w = height
    local wifi_w = Screen:scaleBySize(78)
    local middle_w = math.max(1, width - 2 * button_w - wifi_w)
    local icon_size = math.min(Screen:scaleBySize(26), math.max(1, height - Screen:scaleBySize(10)))
    local row = HorizontalGroup:new{ align = "center" }
    table.insert(row, iconTap(SETTINGS_ICON_PATH or "appbar.settings", button_w, height, function()
        if self.settings_callback then self.settings_callback() end
    end, icon_size, nil, self:isKeyHeaderActionFocused(1)))

    local center = HorizontalGroup:new{ align = "center" }
    table.insert(center, TextWidget:new{
        text = _("Libby Dashboard") .. " (" .. refreshAgeText(self.snapshot, self.refresh_state) .. ")",
        face = Font:getFace("cfont", 18),
        bold = true,
        max_width = math.max(1, middle_w - height - Screen:scaleBySize(8)),
    })
    table.insert(center, HorizontalSpan:new{ width = Screen:scaleBySize(6) })
    table.insert(center, iconTap(REFRESH_ICON_PATH or "cre.render.reload", height, height, function()
        if self.refresh_state ~= "refreshing" and self.refresh_callback then self.refresh_callback() end
    end, icon_size, nil, self:isKeyHeaderActionFocused(2)))
    table.insert(row, CenterContainer:new{ dimen = Geom:new{ w = middle_w, h = height }, center })
    table.insert(row, wifiStatusWidget(wifi_w, height))
    table.insert(row, iconTap(CLOSE_ICON_PATH or "close", button_w, height, function()
        if self.close_callback then self.close_callback() else UIManager:close(self) end
    end, icon_size, nil, self:isKeyHeaderActionFocused(3)))
    return row
end

function LibbyCatalog:tabsWidget(width, height)
    local cards = type(self.snapshot.cards) == "table" and self.snapshot.cards or {}
    local tabs = { { id = "__all__", name = _("All"), count = #(self.snapshot.loans or {}) } }
    for _, card in ipairs(cards) do
        local id = cardId(card)
        local count = 0
        for _, loan in ipairs(self.snapshot.loans or {}) do
            if tostring(loan.card_id or "") == tostring(id or "") then count = count + 1 end
        end
        table.insert(tabs, { id = id, name = cardName(card), count = count })
    end

    local label_h = Screen:scaleBySize(32)
    local tabs_h = math.max(1, height - label_h)
    local library_name = self:selectedLibraryInfo()
    local expand_inset = Screen:scaleBySize(3)
    local expand_w = math.min(Screen:scaleBySize(76), math.max(Screen:scaleBySize(72), math.floor(width * 0.15)))
    local expand_h = math.max(Screen:scaleBySize(24), label_h - 2 * expand_inset)
    local expand_slot_w = expand_w + 2 * expand_inset
    local label_text_w = math.max(1, width - expand_slot_w - 2 * Size.border.thin)
    local label_row = HorizontalGroup:new{ align = "center" }
    table.insert(label_row, CenterContainer:new{
        dimen = Geom:new{ w = label_text_w, h = label_h },
        LeftContainer:new{
            dimen = Geom:new{ w = math.max(1, label_text_w - Screen:scaleBySize(12)), h = label_h },
            TextWidget:new{
                text = _("Library: ") .. tostring(library_name),
                face = Font:getFace("cfont", 15),
                bold = true,
                max_width = math.max(1, label_text_w - Screen:scaleBySize(12)),
            },
        },
    })
    table.insert(label_row, CenterContainer:new{
        dimen = Geom:new{ w = expand_slot_w, h = label_h },
        actionButton(_("Expand"), expand_w, expand_h, true, function()
            self:openExpanded()
        end),
    })
    local label = FrameContainer:new{
        width = width, height = label_h, margin = 0, padding = 0,
        bordersize = Size.border.thin, background = Blitbuffer.COLOR_WHITE, radius = 0,
        label_row,
    }
    local row = HorizontalGroup:new{ align = "center" }
    local count = math.max(1, #tabs)
    local tab_w = math.floor((width - 2 * Size.border.thin) / count)
    local tab_font_size = 15
    local tab_text_w = math.max(1, tab_w - 2 * Screen:scaleBySize(8))
    local tab_face = Font:getFace("cfont", tab_font_size)
    local function fitTabLabel(tab, selected)
        local suffix = " (" .. tostring(tab.count or 0) .. ")"
        local name = tostring(tab.name or "")
        local label = name .. suffix
        local function fits(text)
            return TextWidget:new{
                text = text,
                face = tab_face,
                bold = selected,
            }:getSize().w <= tab_text_w
        end
        if fits(label) then return label end

        local chars = util.splitToChars(name)
        for keep = #chars, 1, -1 do
            local candidate = table.concat(chars, "", 1, keep) .. "…" .. suffix
            if fits(candidate) then return candidate end
        end
        return suffix
    end
    for _, tab in ipairs(tabs) do
        local selected = tostring(self.selected_card_id) == tostring(tab.id)
        local tab_label = fitTabLabel(tab, selected)
        table.insert(row, tappableFrame(
            tab_label,
            tab_w,
            tabs_h,
            selected,
            function() self:selectCard(tab.id) end,
            15
        ))
    end
    return VerticalGroup:new{
        align = "center",
        label,
        CenterContainer:new{ dimen = Geom:new{ w = width, h = tabs_h }, row },
    }
end

function LibbyCatalog:gridWidget(width, height)
    local loans = self:loansForSelectedCard()
    if #loans == 0 then
        return CenterContainer:new{
            dimen = Geom:new{ w = width, h = height },
            TextWidget:new{ text = _("No borrowed or held titles to display."), face = Font:getFace("infofont") },
        }
    end

    local gap = Screen:scaleBySize(8)
    local cols = self.grid_columns
    local rows = self.grid_rows
    local per_page = math.max(1, cols * rows)
    local page_count = math.max(1, math.ceil(#loans / per_page))
    self.shelf_page = math.max(1, math.min(self.shelf_page, page_count))
    local start_index = (self.shelf_page - 1) * per_page + 1
    local cell_w = math.floor((width - (cols + 1) * gap) / cols)
    local cell_h = math.floor((height - (rows + 1) * gap) / rows)
    local label_h = Screen:scaleBySize(22)
    local cover_area_h = math.max(1, cell_h - label_h)
    local cover_w = math.max(1, math.min(cell_w, math.floor(cover_area_h / 1.5)))
    local cover_h = math.max(1, math.min(cover_area_h, math.floor(cover_w * 1.5)))
    local grid = VerticalGroup:new{ align = "center" }
    local index = start_index
    for _ = 1, rows do
        table.insert(grid, VerticalSpan:new{ width = gap })
        local row = HorizontalGroup:new{ align = "center" }
        table.insert(row, HorizontalSpan:new{ width = gap })
        for _ = 1, cols do
            local loan = loans[index]
            if loan and index < start_index + per_page then
                local path = self.cover_path_callback and self.cover_path_callback(loan) or nil
                local card = VerticalGroup:new{ align = "center" }
                table.insert(card, CenterContainer:new{
                    dimen = Geom:new{ w = cell_w, h = cover_area_h },
                    CoverCard:new{
                        loan = loan,
                        dimen = Geom:new{ w = cover_w, h = cover_h },
                        selected = loanKey(loan) == tostring(self.selected_loan_id or ""),
                        focused = self:isKeyFocusedLoan(loan),
                        cover_path = path,
                        callback = function(selected_loan) self:selectLoan(selected_loan) end,
                    },
                })
                table.insert(card, CenterContainer:new{
                    dimen = Geom:new{ w = cell_w, h = label_h },
                    colorAwareTextWidget{
                        text = self:coverStatusText(loan),
                        face = Font:getFace("cfont", 13), bold = true, max_width = cell_w,
                        height = label_h, alignment = "center",
                    },
                })
                table.insert(row, CenterContainer:new{ dimen = Geom:new{ w = cell_w, h = cell_h }, card })
            else
                table.insert(row, HorizontalSpan:new{ width = cell_w })
            end
            table.insert(row, HorizontalSpan:new{ width = gap })
            index = index + 1
        end
        table.insert(grid, row)
    end
    return grid
end

function LibbyCatalog:expandedHeaderWidget(width, height)
    local library_name, loan_count = self:selectedLibraryInfo()
    local icon_w = height
    -- Swap + title + two blank icon slots + Refresh + Holds + View + Close.
    local title_w = math.max(1, width - 7 * icon_w)
    local title_text_w = math.max(1, title_w - Screen:scaleBySize(12))
    local icon_size = math.min(Screen:scaleBySize(26), math.max(1, height - Screen:scaleBySize(10)))
    local title_text, title_face = fitExpandedHeaderText(
        library_name, loan_count, title_text_w, self.refresh_state == "refreshing"
    )

    local row = HorizontalGroup:new{ align = "center" }
    table.insert(row, iconTap(SWAP_ICON_PATH or "cre.render.reload", icon_w, height, function()
        self:cycleExpandedLibraryScope()
    end, icon_size, nil, self:isKeyHeaderActionFocused(1)))
    table.insert(row, CenterContainer:new{
        dimen = Geom:new{ w = title_w, h = height },
        LeftContainer:new{
            dimen = Geom:new{ w = title_text_w, h = height },
            TextWidget:new{
                text = title_text,
                face = title_face,
                bold = true,
                max_width = title_text_w,
            },
        },
    })
    table.insert(row, HorizontalSpan:new{ width = icon_w })
    table.insert(row, HorizontalSpan:new{ width = icon_w })
    table.insert(row, iconTap(REFRESH_ICON_PATH or "cre.render.reload", icon_w, height, function()
        if self.refresh_state ~= "refreshing" and self.refresh_callback then self.refresh_callback() end
    end, icon_size, nil, self:isKeyHeaderActionFocused(2)))
    table.insert(row, CenterContainer:new{
        dimen = Geom:new{ w = icon_w, h = height },
        filterIconTap(HOLDS_ICON_PATH or "bookmark", icon_w, height, self.expanded_holds_only, function()
            self:toggleExpandedHolds()
        end, icon_size, self:isKeyHeaderActionFocused(3)),
    })
    local toggle_icon = self.expanded_view_mode == "grid" and (LIST_ICON_PATH or "appbar.menu") or (GRID_ICON_PATH or "column.two")
    table.insert(row, iconTap(toggle_icon, icon_w, height, function() self:toggleExpandedView() end,
        icon_size, nil, self:isKeyHeaderActionFocused(4)))
    table.insert(row, iconTap(CLOSE_ICON_PATH or "close", icon_w, height, function() self:closeExpanded() end,
        icon_size, nil, self:isKeyHeaderActionFocused(5)))
    return FrameContainer:new{
        width = width, height = height, margin = 0, padding = 0,
        bordersize = Size.border.thin, background = Blitbuffer.COLOR_WHITE,
        row,
    }
end

function LibbyCatalog:expandedGridWidget(width, height)
    local loans = self:loansForSelectedCard()
    if #loans == 0 then
        return CenterContainer:new{
            dimen = Geom:new{ w = width, h = height },
            TextWidget:new{ text = _("No borrowed or held titles to display."), face = Font:getFace("infofont") },
        }
    end

    local gap = Screen:scaleBySize(8)
    local label_h = Screen:scaleBySize(22)
    local cols = self.expanded_grid_columns
    local rows = self.expanded_grid_rows
    local per_page = math.max(1, cols * rows)
    local pages = math.max(1, math.ceil(#loans / per_page))
    self.expanded_grid_page = math.max(1, math.min(self.expanded_grid_page, pages))
    local start_index = (self.expanded_grid_page - 1) * per_page + 1
    local page_items = math.max(0, math.min(per_page, #loans - start_index + 1))
    local visible_rows = math.max(1, math.min(rows, math.ceil(page_items / cols)))
    -- Keep cell sizing based on the configured page rows so short pages stay top-packed.
    local cell_w = math.max(1, math.floor((width - (cols + 1) * gap) / cols))
    local cell_h = math.max(1, math.floor((height - (rows + 1) * gap) / rows))
    local cover_area_h = math.max(1, cell_h - label_h)
    local cover_w = math.max(1, math.min(cell_w, math.floor(cover_area_h / 1.5)))
    local cover_h = math.max(1, math.min(cover_area_h, math.floor(cover_w * 1.5)))

    local grid = VerticalGroup:new{ align = "center" }
    local index = start_index
    for _ = 1, rows do
        table.insert(grid, VerticalSpan:new{ width = gap })
        local row = HorizontalGroup:new{ align = "center" }
        table.insert(row, HorizontalSpan:new{ width = gap })
        for _ = 1, cols do
            local loan = loans[index]
            if loan and index < start_index + per_page then
                local path = self.cover_path_callback and self.cover_path_callback(loan) or nil
                local card = VerticalGroup:new{ align = "center" }
                table.insert(card, coverWidget(loan, cover_w, cover_h, path, false, self:isKeyFocusedLoan(loan)))
                table.insert(card, CenterContainer:new{
                    dimen = Geom:new{ w = cell_w, h = label_h },
                    colorAwareTextWidget{
                        text = loanTimeText(loan),
                        face = Font:getFace("cfont", 14),
                        fgcolor = loanTimeColor(loan),
                        bold = true,
                        max_width = cell_w,
                        height = label_h,
                        alignment = "center",
                    },
                })
                local centered = CenterContainer:new{ dimen = Geom:new{ w = cell_w, h = cell_h }, card }
                table.insert(row, tappableWidget(centered, cell_w, cell_h, function()
                    self:showExpandedDetail(loan)
                end))
            else
                table.insert(row, HorizontalSpan:new{ width = cell_w })
            end
            table.insert(row, HorizontalSpan:new{ width = gap })
            index = index + 1
        end
        table.insert(grid, row)
    end
    return grid
end

function LibbyCatalog:expandedListWidget(width, height)
    local loans = self:loansForSelectedCard()
    if #loans == 0 then
        return CenterContainer:new{
            dimen = Geom:new{ w = width, h = height },
            TextWidget:new{ text = _("No borrowed or held titles to display."), face = Font:getFace("infofont") },
        }
    end

    local rows = self.expanded_list_rows
    local pages = math.max(1, math.ceil(#loans / rows))
    self.expanded_list_page = math.max(1, math.min(self.expanded_list_page, pages))
    local start_index = (self.expanded_list_page - 1) * rows + 1
    local row_h = math.max(1, math.floor(height / rows))
    local pad = Screen:scaleBySize(5)
    local status_face = Font:getFace("cfont", 15)
    -- Reserve enough room for a realistic worst-case hold label, then grow further
    -- if any currently displayed status is wider (important for translations).
    local status_probe = TextWidget:new{ text = "#1000 in line · 365 days", face = status_face, bold = true }
    local desired_loan_w = status_probe:getSize().w + 2 * pad
    for _, candidate in ipairs(loans) do
        local candidate_probe = TextWidget:new{ text = loanTimeText(candidate), face = status_face, bold = true }
        desired_loan_w = math.max(desired_loan_w, candidate_probe:getSize().w + 2 * pad)
    end
    local loan_w = math.min(desired_loan_w, math.floor(width * 0.40))
    local list = VerticalGroup:new{ align = "center" }

    for offset = 0, rows - 1 do
        local loan = loans[start_index + offset]
        if loan then
            local cover_h = math.max(1, row_h - 2 * pad)
            local cover_w = math.max(1, math.floor(cover_h * 0.66))
            local meta_w = math.max(1, width - cover_w - loan_w - 5 * pad)
            local path = self.cover_path_callback and self.cover_path_callback(loan) or nil
            local meta = VerticalGroup:new{ align = "left" }
            table.insert(meta, TextWidget:new{
                text = safeText(loan.title or _("Untitled"), 120),
                face = Font:getFace("cfont", 18),
                bold = true,
                max_width = meta_w,
            })
            table.insert(meta, TextWidget:new{
                text = safeText(loan.author or _("N/A"), 90),
                face = Font:getFace("smallinfofont", 14),
                max_width = meta_w,
            })
            local fallback_library = self:selectedLibraryInfo()
            table.insert(meta, TextWidget:new{
                text = tostring(loan.library or fallback_library),
                face = Font:getFace("smallinfofont", 13),
                max_width = meta_w,
            })

            local row_content = HorizontalGroup:new{ align = "center" }
            table.insert(row_content, HorizontalSpan:new{ width = pad })
            table.insert(row_content, coverWidget(loan, cover_w, cover_h, path, false))
            table.insert(row_content, HorizontalSpan:new{ width = 2 * pad })
            table.insert(row_content, CenterContainer:new{
                dimen = Geom:new{ w = meta_w, h = row_h },
                LeftContainer:new{ dimen = Geom:new{ w = meta_w, h = row_h }, meta },
            })
            table.insert(row_content, CenterContainer:new{
                dimen = Geom:new{ w = loan_w, h = row_h },
                colorAwareTextWidget{
                    text = loanTimeText(loan),
                    face = status_face,
                    fgcolor = loanTimeColor(loan),
                    bold = true,
                    max_width = loan_w,
                    alignment = "center",
                },
            })
            table.insert(row_content, HorizontalSpan:new{ width = pad })
            local frame = FrameContainer:new{
                width = width, height = row_h, margin = 0, padding = 0,
                bordersize = self:isKeyFocusedLoan(loan) and math.max(Size.border.default, Screen:scaleBySize(3)) or Size.border.thin,
                color = Blitbuffer.COLOR_BLACK, background = Blitbuffer.COLOR_WHITE,
                row_content,
            }
            table.insert(list, tappableWidget(frame, width, row_h, function()
                self:showExpandedDetail(loan)
            end))
        else
            table.insert(list, VerticalSpan:new{ width = row_h })
        end
    end
    return list
end

function LibbyCatalog:expandedPaginationWidget(width, height)
    local pages = self:expandedPageCount()
    local current = math.max(1, math.min(self:expandedPage(), pages))
    local can_back = current > 1
    local can_forward = current < pages
    local nav_w = math.floor(width * 0.75)
    local icon_size = math.floor(height * 0.62)
    local function slot(ratio) return math.max(1, math.floor(nav_w * ratio)) end
    local first = Button:new{
        icon = "chevron.first", icon_width = icon_size, icon_height = icon_size,
        width = slot(0.18), enabled = can_back, callback = function() self:setExpandedPage(1) end,
        margin = 0, bordersize = 0, show_parent = self,
    }
    local prev = Button:new{
        icon = "chevron.left", icon_width = icon_size, icon_height = icon_size,
        width = slot(0.18), enabled = can_back, callback = function() self:setExpandedPage(current - 1) end,
        margin = 0, bordersize = 0, show_parent = self,
    }
    local page = Button:new{
        text = string.format(_("Page %d of %d"), current, pages),
        text_font_face = "cfont", text_font_size = 15,
        width = slot(0.28), margin = 0, bordersize = 0, show_parent = self,
    }
    local next_btn = Button:new{
        icon = "chevron.right", icon_width = icon_size, icon_height = icon_size,
        width = slot(0.18), enabled = can_forward, callback = function() self:setExpandedPage(current + 1) end,
        margin = 0, bordersize = 0, show_parent = self,
    }
    local last = Button:new{
        icon = "chevron.last", icon_width = icon_size, icon_height = icon_size,
        width = slot(0.18), enabled = can_forward, callback = function() self:setExpandedPage(pages) end,
        margin = 0, bordersize = 0, show_parent = self,
    }
    return CenterContainer:new{
        dimen = Geom:new{ w = width, h = height },
        HorizontalGroup:new{ align = "center", first, prev, page, next_btn, last },
    }
end

function LibbyCatalog:expandedDetailWidget(width, height, tall_portrait, cover_reference_height)
    local loan = self:selectedLoan()
    if not loan then return nil end

    local pad = Size.padding.default
    local top_inset = math.max(5, Screen:scaleBySize(5))
    local cover_top_inset = math.max(1, Screen:scaleBySize(1))
    local action_h = Screen:scaleBySize(34)
    local gap = Screen:scaleBySize(8)
    local on_hold = loan.on_hold == true
    local hold_borrowable = on_hold and holdBorrowable(loan)
    local show_return = self.return_enabled == true and loan.extended_loan ~= true and not on_hold
    local show_delete = loan.extended_loan == true
    -- Every detail card includes Book Notes immediately before Close.
    local button_count = on_hold and (hold_borrowable and 4 or 3) or ((show_return or show_delete) and 4 or 3)
    local geometry = CatalogLayout.expandedDetailGeometry(
        width,
        height,
        pad,
        action_h,
        gap,
        button_count,
        function(value) return Screen:scaleBySize(value) end,
        tall_portrait
    )
    local cover_w = geometry.cover_width
    local cover_h = geometry.cover_height
    local info_w = geometry.info_width
    local button_w = geometry.button_width
    if not tall_portrait and tonumber(cover_reference_height) then
        -- Notes-capable cards get extra vertical room, but every cover keeps the
        -- compact reference size used before that extra room is added.
        local normal_button_count = self.return_enabled == true and 4 or 3
        local reference_geometry = CatalogLayout.expandedDetailGeometry(
            width,
            cover_reference_height,
            pad,
            action_h,
            gap,
            normal_button_count,
            function(value) return Screen:scaleBySize(value) end,
            false
        )
        cover_w = reference_geometry.cover_width
        cover_h = reference_geometry.cover_height
        info_w = math.max(1, width - cover_w - 4 * pad)
    end
    local path = self.cover_path_callback and self.cover_path_callback(loan) or nil

    -- Metadata belongs only in the right-hand column. Book Notes is deliberately
    -- kept out of this group so it can occupy its own full-width section below.
    local metadata = VerticalGroup:new{ align = "left" }
    table.insert(metadata, TextWidget:new{
        text = safeText(loan.title or _("Untitled"), 120),
        face = Font:getFace("cfont", on_hold and 20 or 22), bold = true, max_width = info_w,
    })
    local detail_face = Font:getFace("smallinfofont", on_hold and 14 or 16)
    local compact_trim = math.max(2, Screen:scaleBySize(4))
    local function insertCompactDetailRow(group, label_text, value_text, value_color, bold)
        local label = TextWidget:new{ text = label_text, face = detail_face }
        local row_h = math.max(1, label:getSize().h - compact_trim)
        local value_w = math.max(1, info_w - label:getSize().w)
        label.forced_height = row_h
        table.insert(group, HorizontalGroup:new{
            align = "center",
            label,
            colorAwareTextWidget{
                text = value_text,
                face = detail_face,
                fgcolor = value_color or Blitbuffer.COLOR_BLACK,
                bold = bold == true,
                max_width = value_w,
                forced_height = row_h,
            },
        })
    end
    local detail_rows = {
        { _("Author: "), safeText(loan.author or _("N/A"), 80) },
        { _("Series: "), safeText(loan.series or _("N/A"), 80) },
        { _("Series Index: "), safeText(loan.series_index ~= nil and tostring(loan.series_index) or _("N/A"), 40) },
        { _("Format: "), mediaLabel(loan) },
        { _("Library: "), safeText(loan.library or _("N/A"), 100) },
    }
    for _, row in ipairs(detail_rows) do
        insertCompactDetailRow(metadata, row[1], row[2])
    end
    if on_hold then
        table.insert(metadata, TextWidget:new{
            text = _("HOLD STATUS"), face = detail_face, bold = true, max_width = info_w,
        })
        local hold_rows = {
            { _("Status: "), holdDetailedStatus(loan) },
        }
        local position = tonumber(loan.hold_list_position)
        if position and position > 0 then
            table.insert(hold_rows, { _("Position: "), string.format(_("#%d in line"), position) })
        end
        local wait = holdWaitText(loan.estimated_wait_days)
        if wait then table.insert(hold_rows, { _("Estimated wait: "), wait }) end
        local copies = tonumber(loan.owned_copies)
        if copies ~= nil then table.insert(hold_rows, { _("Copies: "), tostring(copies) }) end
        if loan.suspension_flag == true and type(loan.suspension_end) == "string" and loan.suspension_end ~= "" then
            table.insert(hold_rows, { _("Suspended until: "), safeText(loan.suspension_end, 40) })
        end
        for _, row in ipairs(hold_rows) do
            insertCompactDetailRow(metadata, row[1], row[2], Blitbuffer.COLOR_BLACK, false)
        end
    else
        insertCompactDetailRow(
            metadata,
            loan.extended_loan == true and _("Status: ") or _("Expires On: "),
            loanTimeText(loan),
            loanTimeColor(loan),
            false
        )
    end

    local downloaded_path = self.downloaded_path_callback and self.downloaded_path_callback(loan) or nil
    local locally_available = type(downloaded_path) == "string" and downloaded_path ~= ""
    local network_ok = self.network_available_callback == nil or self.network_available_callback()
    local extended = loan.extended_loan == true
    local action
    if on_hold then
        local hold_action_text = hold_borrowable and _("Borrow") or _("Cancel Hold")
        action = actionButton(hold_action_text, button_w, action_h, network_ok, function()
            if hold_borrowable then
                if self.borrow_hold_callback then self.borrow_hold_callback(loan) end
            elseif self.cancel_hold_callback then
                self.cancel_hold_callback(loan)
            end
        end, self:isKeyDetailActionFocused(1))
    elseif locally_available then
        action = actionButton(_("Open"), button_w, action_h, true, function()
            if self.open_callback then self.open_callback(downloaded_path) end
        end, self:isKeyDetailActionFocused(1))
    elseif extended then
        action = outlinedLabel(_("Unavailable"), button_w, action_h, self:isKeyDetailActionFocused(1))
    elseif downloadFormat(loan) and loan.media_type ~= "audiobook" and loan.media_type ~= "magazine" then
        action = actionButton(_("Download"), button_w, action_h, network_ok, function()
            if self.download_callback then self.download_callback(loan) end
        end, self:isKeyDetailActionFocused(1))
    else
        action = outlinedLabel(_("Unsupported"), button_w, action_h, self:isKeyDetailActionFocused(1))
    end

    local actions = HorizontalGroup:new{ align = "center" }
    table.insert(actions, action)
    if on_hold and hold_borrowable then
        table.insert(actions, HorizontalSpan:new{ width = gap })
        table.insert(actions, actionButton(_("Cancel Hold"), button_w, action_h, network_ok, function()
            if self.cancel_hold_callback then self.cancel_hold_callback(loan) end
        end, self:isKeyDetailActionFocused(2)))
    elseif show_return then
        table.insert(actions, HorizontalSpan:new{ width = gap })
        table.insert(actions, actionButton(_("Return"), button_w, action_h, network_ok, function()
            if self.return_callback then self.return_callback(loan) end
        end, self:isKeyDetailActionFocused(2)))
    elseif show_delete then
        table.insert(actions, HorizontalSpan:new{ width = gap })
        table.insert(actions, actionButton(_("Delete"), button_w, action_h, true, function()
            if self.delete_callback then self.delete_callback(loan) end
        end, self:isKeyDetailActionFocused(2)))
    end

    -- Notes are a book action, not a Hold-only action.
    table.insert(actions, HorizontalSpan:new{ width = gap })
    local note_label = self:bookNote(loan) == "" and _("Add Note") or _("Edit Note")
    table.insert(actions, actionButton(note_label, button_w, action_h, true, function()
        if self.edit_book_note_callback then self.edit_book_note_callback(loan) end
    end, self:isKeyDetailActionFocused(button_count - 1)))

    table.insert(actions, HorizontalSpan:new{ width = gap })
    table.insert(actions, actionButton(_("Close"), button_w, action_h, true, function()
        self:hideExpandedDetail()
    end, self:isKeyDetailActionFocused(button_count)))

    local action_band_h = action_h + math.max(4, Screen:scaleBySize(4))
    local metadata_h = math.max(1, metadata:getSize().h)
    local top_row_h = math.max(cover_h + cover_top_inset, metadata_h)

    -- Give both children the same outer height and pin their contents to the top.
    -- This prevents HorizontalGroup from vertically centering a shorter cover.
    local top_row = HorizontalGroup:new{ align = "center" }
    table.insert(top_row, HorizontalSpan:new{ width = pad })
    table.insert(top_row, TopContainer:new{
        dimen = Geom:new{ w = cover_w, h = top_row_h },
        VerticalGroup:new{
            align = "left",
            VerticalSpan:new{ width = cover_top_inset },
            coverWidget(loan, cover_w, cover_h, path, true),
        },
    })
    table.insert(top_row, HorizontalSpan:new{ width = 2 * pad })
    table.insert(top_row, TopContainer:new{
        dimen = Geom:new{ w = info_w, h = top_row_h },
        metadata,
    })
    table.insert(top_row, HorizontalSpan:new{ width = pad })

    local content_stack = VerticalGroup:new{ align = "left" }
    table.insert(content_stack, VerticalSpan:new{ width = top_inset })
    table.insert(content_stack, top_row)

    local notes_w = math.max(1, width - 2 * pad)
    local note = self:bookNote(loan)
    local notes = VerticalGroup:new{ align = "left" }
    table.insert(notes, TextWidget:new{
        text = _("Book Notes"), face = Font:getFace("smallinfofont", 14), bold = true, max_width = notes_w,
    })
    table.insert(notes, TextBoxWidget:new{
        text = note ~= "" and safeText(note, 240) or _("No note added."),
        face = Font:getFace("smallinfofont", 14),
        width = notes_w,
        height = Screen:scaleBySize(36),
        alignment = "left",
        line_height = 0,
        use_xtext = true,
    })
    table.insert(content_stack, VerticalSpan:new{ width = Screen:scaleBySize(2) })
    table.insert(content_stack, LeftContainer:new{
        dimen = Geom:new{ w = width, h = notes:getSize().h },
        HorizontalGroup:new{
            align = "center",
            HorizontalSpan:new{ width = pad },
            notes,
            HorizontalSpan:new{ width = pad },
        },
    })
    table.insert(content_stack, VerticalSpan:new{ width = math.max(2, Screen:scaleBySize(2)) })

    local content_h = math.max(1, content_stack:getSize().h)
    local top_content = TopContainer:new{
        dimen = Geom:new{ w = width, h = content_h },
        content_stack,
    }
    local frame_h = math.min(
        self.height - Screen:scaleBySize(16),
        content_h + action_band_h + 2 * Size.border.default
    )

    return FrameContainer:new{
        width = width, height = frame_h, margin = 0, padding = 0,
        bordersize = Size.border.default, background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "center",
            top_content,
            CenterContainer:new{
                dimen = Geom:new{ w = width, h = action_band_h },
                actions,
            },
        },
    }
end

function LibbyCatalog:expandedDetailLayer(modal_width, modal_height, tall_portrait, cover_reference_height)
    local detail = self:expandedDetailWidget(modal_width, modal_height, tall_portrait, cover_reference_height)
    local detail_size = detail:getSize()
    local modal_rect = Geom:new{
        x = math.floor((self.width - detail_size.w) / 2),
        y = math.floor((self.height - detail_size.h) / 2),
        w = detail_size.w,
        h = detail_size.h,
    }
    local layer = InputContainer:new{
        dimen = Geom:new{ w = self.width, h = self.height },
        stop_events_propagation = true,
        CenterContainer:new{
            dimen = Geom:new{ w = self.width, h = self.height },
            detail,
        },
    }
    layer.ges_events = {
        TapDismissExpandedDetail = { GestureRange:new{ ges = "tap", range = layer.dimen } },
    }
    layer.onTapDismissExpandedDetail = function(_, ges)
        if ges and ges.pos and ges.pos:notIntersectWith(modal_rect) then
            self:hideExpandedDetail()
        end
        return true
    end
    return layer
end

function LibbyCatalog:paginationWidget(width, height)
    local pages = self:pageCount()
    local can_back = self.shelf_page > 1
    local can_forward = self.shelf_page < pages
    local nav_w = math.floor(width * 0.75)
    local icon_size = math.floor(height * 0.62)
    local function slot(ratio) return math.max(1, math.floor(nav_w * ratio)) end
    local common = { margin = 0, bordersize = 0, show_parent = self }
    local first = Button:new{
        icon = "chevron.first", icon_width = icon_size, icon_height = icon_size,
        width = slot(0.18), enabled = can_back, callback = function() self:gotoShelfPage(1) end,
        margin = common.margin, bordersize = common.bordersize, show_parent = self,
    }
    local prev = Button:new{
        icon = "chevron.left", icon_width = icon_size, icon_height = icon_size,
        width = slot(0.18), enabled = can_back, callback = function() self:gotoShelfPage(self.shelf_page - 1) end,
        margin = common.margin, bordersize = common.bordersize, show_parent = self,
    }
    local page = Button:new{
        text = string.format(_("Page %d of %d"), self.shelf_page, pages),
        text_font_face = "cfont", text_font_size = 15,
        width = slot(0.28), margin = 0, bordersize = 0, show_parent = self,
    }
    local next_btn = Button:new{
        icon = "chevron.right", icon_width = icon_size, icon_height = icon_size,
        width = slot(0.18), enabled = can_forward, callback = function() self:gotoShelfPage(self.shelf_page + 1) end,
        margin = 0, bordersize = 0, show_parent = self,
    }
    local last = Button:new{
        icon = "chevron.last", icon_width = icon_size, icon_height = icon_size,
        width = slot(0.18), enabled = can_forward, callback = function() self:gotoShelfPage(pages) end,
        margin = 0, bordersize = 0, show_parent = self,
    }
    return CenterContainer:new{
        dimen = Geom:new{ w = width, h = height },
        HorizontalGroup:new{ align = "center", first, prev, page, next_btn, last },
    }
end

function LibbyCatalog:updateItems()
    DiagnosticLog.log("[catalog] updateItems:start")
    self.width = Screen:getWidth()
    self.height = Screen:getHeight()
    if self.dimen then
        self.dimen.w = self.width
        self.dimen.h = self.height
    else
        self.dimen = Geom:new{ w = self.width, h = self.height }
    end

    local footer_height = Screen:scaleBySize(32)
        + 2 * Screen:scaleBySize(4)
        + Screen:scaleBySize(12)
    local overlap

    if self.expanded then
        local header_height = Screen:scaleBySize(42)
        local content_height = math.max(Screen:scaleBySize(100), self.height - header_height - footer_height)
        local shelf = self.expanded_view_mode == "list"
            and self:expandedListWidget(self.width, content_height)
            or self:expandedGridWidget(self.width, content_height)
        local content = VerticalGroup:new{
            align = "center",
            self:expandedHeaderWidget(self.width, header_height),
            shelf,
        }
        local main_frame = FrameContainer:new{
            width = self.width,
            height = self.height - footer_height,
            margin = 0,
            padding = 0,
            bordersize = 0,
            background = Blitbuffer.COLOR_WHITE,
            content,
        }
        overlap = TopFirstOverlapGroup:new{
            dimen = Geom:new{ w = self.width, h = self.height },
            allow_mirroring = false,
            main_frame,
        }
        overlap[#overlap + 1] = BottomContainer:new{
            dimen = Geom:new{ w = self.width, h = self.height },
            FrameContainer:new{
                width = self.width,
                height = footer_height,
                margin = 0,
                padding = 0,
                bordersize = 0,
                background = Blitbuffer.COLOR_WHITE,
                self:expandedPaginationWidget(self.width, footer_height),
            },
        }
        if self.expanded_detail_visible and self:selectedLoan() then
            local modal = CatalogLayout.expandedModalGeometry(
                self.width,
                self.height,
                function(value) return Screen:scaleBySize(value) end
            )
            -- The original modal height is now only the compact cover-size reference.
            -- expandedDetailWidget sizes the visible card from its actual content.
            local cover_reference_height = modal.height
            overlap[#overlap + 1] = self:expandedDetailLayer(modal.width, modal.height, modal.tall, cover_reference_height)
        end
    else
        local header_height = Screen:scaleBySize(40)
        local top_height = math.floor(self.height * 0.30)
        local tabs_height = Screen:scaleBySize(56)
        local content_height = math.max(
            Screen:scaleBySize(100),
            self.height - header_height - top_height - tabs_height - footer_height
        )
        local content = VerticalGroup:new{
            align = "center",
            self:headerWidget(self.width, header_height),
            self:heroWidget(self.width, top_height),
            self:tabsWidget(self.width, tabs_height),
            self:gridWidget(self.width, content_height),
        }
        local main_frame = FrameContainer:new{
            width = self.width,
            height = self.height - footer_height,
            margin = 0,
            padding = 0,
            bordersize = 0,
            background = Blitbuffer.COLOR_WHITE,
            content,
        }
        overlap = OverlapGroup:new{
            dimen = Geom:new{ w = self.width, h = self.height },
            allow_mirroring = false,
            main_frame,
        }
        overlap[#overlap + 1] = BottomContainer:new{
            dimen = Geom:new{ w = self.width, h = self.height },
            FrameContainer:new{
                width = self.width,
                height = footer_height,
                margin = 0,
                padding = 0,
                bordersize = 0,
                background = Blitbuffer.COLOR_WHITE,
                self:paginationWidget(self.width, footer_height),
            },
        }
    end

    DiagnosticLog.log("[catalog] updateItems:old-widget-free:start")
    if self[1] and self[1].free then self[1]:free() end
    DiagnosticLog.log("[catalog] updateItems:old-widget-free:end")
    self[1] = overlap

    DiagnosticLog.log("[catalog] updateItems:setDirty:start")
    UIManager:setDirty(self, function()
        return "ui", self.dimen
    end)
    DiagnosticLog.log("[catalog] updateItems:setDirty:end")
    DiagnosticLog.log("[catalog] updateItems:end")
end

function LibbyCatalog:refreshSnapshot(snapshot, state)
    DiagnosticLog.log("[catalog] refreshSnapshot:start", "state=" .. tostring(state))
    self.snapshot = snapshot or {}
    self.refresh_state = state
    self.selected_loan_id = nil
    self.expanded_detail_visible = false
    self:updateItems()
    DiagnosticLog.log("[catalog] refreshSnapshot:end")
end

function LibbyCatalog:onNetworkConnected()
    self:updateItems()
end

function LibbyCatalog:onNetworkDisconnected()
    self:updateItems()
end

function LibbyCatalog:onLeftButtonTap()
    if self.settings_callback then
        self.settings_callback()
    elseif self.close_callback then
        self.close_callback()
    else
        UIManager:close(self)
    end
    return true
end

function LibbyCatalog:onClose()
    if self.close_callback then
        self.close_callback()
    else
        UIManager:close(self)
    end
    return true
end

return LibbyCatalog
