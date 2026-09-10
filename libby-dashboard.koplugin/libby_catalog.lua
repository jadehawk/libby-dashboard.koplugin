local Blitbuffer = require("ffi/blitbuffer")
local DiagnosticLog = require("diagnostic_log")
local Dpad = require("libby_dpad")
local MediaRacks = require("libby_media_racks")
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

local function safeText(value, max_len)
    local text = tostring(value or ""):gsub("[%z\1-\31\127]", " "):gsub("%s+", " ")
    if #text <= (max_len or 96) then return text end
    return text:sub(1, math.max(1, (max_len or 96) - 3)) .. "..."
end

local function rackGroupHeaderWidget(library_name, item_count, width, height)
    local name = safeText(library_name ~= "" and library_name or _("Unknown Library"), 100)
    local label = string.format("%s (%d)", name, tonumber(item_count) or 0)
    return FrameContainer:new{
        width = width,
        height = height,
        margin = 0,
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_LIGHT_GRAY,
        CenterContainer:new{
            dimen = Geom:new{ w = width, h = height },
            TextWidget:new{
                text = label,
                face = Font:getFace("cfont", 13),
                bold = true,
                max_width = math.max(1, width - 2 * Screen:scaleBySize(8)),
            },
        },
    }
end

local function measureHeaderText(text, face)
    local probe = TextWidget:new{ text = text, face = face, bold = true }
    return probe:getSize().w
end

local function fitBrowserHeaderText(library_name, loan_count, max_width, refreshing)
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

local function itemKey(loan)
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

local function cardId(card)
    return card and (card.id or card.cardId)
end

local function rawCardName(card)
    return tostring(card and (card.name or card.libraryName or card.id) or _("Library"))
end

function LibbyCatalog:init()
    self.settings = self.settings or {}
    self.snapshot = self.snapshot or {}
    self.width = Screen:getWidth()
    self.height = Screen:getHeight()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self.selected_scope_id = self.settings.libby_browser_scope_id or MediaRacks.ALL_SCOPE
    self.selected_loan_id = nil
    self.detail_visible = false
    self.holds_only = false
    self.browser_view_mode = self.settings.libby_browser_view_mode == "list" and "list" or "grid"
    self.browser_grid_columns = math.max(2, math.min(8, tonumber(self.settings.libby_browser_grid_columns) or 4))
    self.browser_grid_rows = math.max(1, math.min(6, tonumber(self.settings.libby_browser_grid_rows) or 3))
    self.browser_grid_page = 1
    self.browser_list_rows = math.max(4, math.min(12, tonumber(self.settings.libby_browser_list_rows) or 7))
    self.browser_list_page = 1
    self.key_focus_active = not Dpad.is_touch_device(Device)
    self.key_focus_region = self.key_focus_active and "books" or nil
    self.key_focus_index = nil
    self.key_header_index = 1
    self.key_detail_action_index = 1
    self.ges_events = {
        BrowserSwipeNext = { GestureRange:new{ ges = "swipe", range = self.dimen, direction = "west" } },
        BrowserSwipePrev = { GestureRange:new{ ges = "swipe", range = self.dimen, direction = "east" } },
    }
    self.key_events = Dpad.catalog_key_events(Device)
    if self.key_focus_active then
        local loans = self:itemsForSelectedScope()
        self.key_focus_index = Dpad.first_index_for_page(self:browserPage(), self:keyFocusPerPage(), #loans)
        if not self.key_focus_index then
            self.key_focus_region = "header"
            self.key_focus_waiting_for_items = true
        end
    end
    self:updateItems()
end

function LibbyCatalog:keyFocusPerPage()
    if self.browser_view_mode == "list" then return math.max(1, self.browser_list_rows) end
    return math.max(1, self.browser_grid_columns * self.browser_grid_rows)
end

function LibbyCatalog:keyFocusColumns()
    if self.browser_view_mode == "list" then return 1 end
    return self.browser_grid_columns
end

function LibbyCatalog:keyCurrentPage()
    return self:browserPage()
end

function LibbyCatalog:setKeyPageSilently(page)
    local loans = self:itemsForSelectedScope()
    local _, _, pages = Dpad.page_bounds(page, self:keyFocusPerPage(), #loans)
    local next_page = math.max(1, math.min(pages, tonumber(page) or 1))
    if self.browser_view_mode == "list" then
        self.browser_list_page = next_page
    else
        self.browser_grid_page = next_page
    end
    return next_page
end

function LibbyCatalog:activateKeyFocus()
    self.key_focus_active = true
    local loans = self:itemsForSelectedScope()
    if #loans == 0 then
        self.key_focus_region = "header"
        self.key_focus_index = nil
        return false
    end
    self.key_focus_region = "books"
    local selected = Dpad.find_index(loans, self.selected_loan_id, itemKey)
    local page = Dpad.page_for(selected or 1, self:keyFocusPerPage())
    self:setKeyPageSilently(page)
    self.key_focus_index = selected or Dpad.first_index_for_page(page, self:keyFocusPerPage(), #loans)
    if self.detail_visible then self.key_detail_action_index = 1 end
    return self.key_focus_index ~= nil
end

function LibbyCatalog:revealKeyFocus()
    if self.key_focus_active then return false end
    self.key_focus_active = true
    local loans = self:itemsForSelectedScope()
    if #loans > 0 then
        self.key_focus_region = "books"
        self.key_focus_index = Dpad.first_index_for_page(self:keyCurrentPage(), self:keyFocusPerPage(), #loans)
    else
        self.key_focus_region = "header"
        self.key_focus_index = nil
    end
    self:updateItems()
    return true
end

function LibbyCatalog:focusedKeyItem()
    if not self.key_focus_active or self.key_focus_region ~= "books" then return nil end
    local loans = self:itemsForSelectedScope()
    local index = tonumber(self.key_focus_index)
    return index and loans[index] or nil
end

function LibbyCatalog:isKeyFocusedItem(loan)
    local focused = self:focusedKeyItem()
    return focused ~= nil and itemKey(focused) == itemKey(loan) and not self.detail_visible
end

function LibbyCatalog:syncKeyFocusPage()
    if not self.key_focus_index then return end
    self:setKeyPageSilently(Dpad.page_for(self.key_focus_index, self:keyFocusPerPage()))
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
    if loan and loan.media_type == "magazine" then
        if loan.magazine_new_issue == true then return _("NEW ISSUE") end
        if type(loan.magazine_frequency) == "string" and loan.magazine_frequency ~= "" then
            return loan.magazine_frequency
        end
        return _("Read on Libby")
    end
    if loan and loan.media_type == "audiobook" then return _("Listen on Libby") end
    if not loan or not downloadFormat(loan) then return _("Read on Libby") end
    return loanTimeText(loan)
end

function LibbyCatalog:keyDetailActions()
    local loan = self:selectedItem()
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
    elseif loan.media_type == "audiobook" or loan.media_type == "magazine" then
        table.insert(actions, function()
            if self.libby_media_callback then self.libby_media_callback(loan) end
        end)
    else
        table.insert(actions, false)
    end

    if self.return_enabled == true and not extended and not on_hold and loan.magazine_subscription ~= true then
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
    table.insert(actions, function() self:hideDetail() end)
    return actions
end

function LibbyCatalog:isKeyDetailActionFocused(index)
    return self.key_focus_active and self.detail_visible
        and tonumber(self.key_detail_action_index or 1) == index
end

function LibbyCatalog:keyHeaderActions()
    return {
        function() self:cycleBrowserScope() end,
        not MediaRacks.is_synthetic(self.selected_scope_id) and function() self:toggleBrowserHolds() end or false,
        self.refresh_state ~= "refreshing" and self.refresh_callback
            and function() self.refresh_callback() end or false,
        self.settings_callback and function() self.settings_callback() end or false,
        function() self:toggleBrowserView() end,
        function()
            if self.close_callback then self.close_callback() else UIManager:close(self) end
        end,
    }
end

function LibbyCatalog:isKeyHeaderActionFocused(index)
    return self.key_focus_active and not self.detail_visible
        and self.key_focus_region == "header"
        and tonumber(self.key_header_index or 1) == index
end

function LibbyCatalog:enterKeyHeaderFocus(index)
    self.key_focus_active = true
    self.key_focus_region = "header"
    local actions = self:keyHeaderActions()
    self.key_header_index = Dpad.active_action_index(actions, tonumber(index) or tonumber(self.key_header_index) or 1) or 1
    self:updateItems()
    return true
end

function LibbyCatalog:moveKeyFocus(direction)
    if self:revealKeyFocus() then return true end
    if self.detail_visible then
        local actions = self:keyDetailActions()
        if #actions > 0 then
            local delta = (direction == "right" or direction == "down") and 1 or -1
            self.key_detail_action_index = Dpad.next_action_index(actions, self.key_detail_action_index, delta)
                or Dpad.active_action_index(actions, 1) or 1
            self:updateItems()
        end
        return true
    end

    local loans = self:itemsForSelectedScope()
    local per_page = self:keyFocusPerPage()
    local current_page = self:keyCurrentPage()
    local first, last, page_count = Dpad.page_bounds(current_page, per_page, #loans)

    if self.key_focus_region == "header" then
        local actions = self:keyHeaderActions()
        local count = math.max(1, #actions)
        local header_index = Dpad.active_action_index(actions, self.key_header_index) or 1
        self.key_header_index = header_index
        if direction == "down" then
            if #loans == 0 then return true end
            self.key_focus_region = "books"
            if self.browser_view_mode == "list" then
                self.key_focus_index = first
            else
                local column = math.max(1, math.min(self:keyFocusColumns(), header_index))
                self.key_focus_index = math.min(last, first + column - 1)
            end
        elseif direction == "left" then
            local next_index = Dpad.next_action_index(actions, header_index, -1)
            if header_index == 1 and current_page > 1 then
                self:setKeyPageSilently(current_page - 1)
            elseif next_index then
                self.key_header_index = next_index
            end
        elseif direction == "right" then
            local next_index = Dpad.next_action_index(actions, header_index, 1)
            if header_index == count and current_page < page_count then
                self:setKeyPageSilently(current_page + 1)
            elseif next_index then
                self.key_header_index = next_index
            end
        end
        self:updateItems()
        return true
    end

    if #loans == 0 then return self:enterKeyHeaderFocus(1) end
    if not self.key_focus_index or self.key_focus_index < first or self.key_focus_index > last then
        self.key_focus_index = first
    end
    local local_index = self.key_focus_index - first + 1

    if self.browser_view_mode == "list" then
        if direction == "up" then
            if self.key_focus_index > first then
                self.key_focus_index = self.key_focus_index - 1
            else
                return self:enterKeyHeaderFocus(1)
            end
        elseif direction == "down" then
            if self.key_focus_index < last then self.key_focus_index = self.key_focus_index + 1 end
        elseif direction == "left" then
            if current_page > 1 then
                self:setKeyPageSilently(current_page - 1)
                self.key_focus_index = Dpad.first_index_for_page(current_page - 1, per_page, #loans)
            end
        elseif direction == "right" then
            if current_page < page_count then
                self:setKeyPageSilently(current_page + 1)
                self.key_focus_index = Dpad.first_index_for_page(current_page + 1, per_page, #loans)
            end
        end
        self:updateItems()
        return true
    end

    local columns = self:keyFocusColumns()
    if MediaRacks.is_synthetic(self.selected_scope_id) then
        local positions = MediaRacks.grid_positions(loans, first, last, columns)
        local position = positions[self.key_focus_index]
        if direction == "up" and position and position.row == 1 then
            return self:enterKeyHeaderFocus(1)
        end
        local next_index = Dpad.move_visual_grid(positions, self.key_focus_index, direction)
        if next_index == self.key_focus_index and direction == "left"
            and self.key_focus_index == first and current_page > 1 then
            self:setKeyPageSilently(current_page - 1)
            self.key_focus_index = Dpad.first_index_for_page(current_page - 1, per_page, #loans)
        elseif next_index == self.key_focus_index and direction == "right"
            and self.key_focus_index == last and current_page < page_count then
            self:setKeyPageSilently(current_page + 1)
            self.key_focus_index = Dpad.first_index_for_page(current_page + 1, per_page, #loans)
        else
            self.key_focus_index = next_index
        end
        self:updateItems()
        return true
    end
    if direction == "up" and local_index <= columns then
        return self:enterKeyHeaderFocus(math.min(#self:keyHeaderActions(), local_index))
    end
    local next_index, page_delta = Dpad.move_page_local(
        self.key_focus_index, direction, columns, current_page, per_page, #loans
    )
    if page_delta ~= 0 then self:setKeyPageSilently(current_page + page_delta) end
    self.key_focus_index = next_index
    self:updateItems()
    return true
end

function LibbyCatalog:onDpadUp() return self:moveKeyFocus("up") end
function LibbyCatalog:onDpadDown() return self:moveKeyFocus("down") end
function LibbyCatalog:onDpadLeft() return self:moveKeyFocus("left") end
function LibbyCatalog:onDpadRight() return self:moveKeyFocus("right") end

function LibbyCatalog:changeKeyPage(delta)
    if self.detail_visible then return true end
    if self:revealKeyFocus() then return true end
    local loans = self:itemsForSelectedScope()
    if #loans == 0 then return true end
    local per_page = self:keyFocusPerPage()
    local current = self:keyCurrentPage()
    local _, _, page_count = Dpad.page_bounds(current, per_page, #loans)
    local next_page = math.max(1, math.min(page_count, current + delta))
    self:setKeyPageSilently(next_page)
    self.key_focus_region = "books"
    self.key_focus_index = Dpad.first_index_for_page(next_page, per_page, #loans)
    self:updateItems()
    return true
end

function LibbyCatalog:onDpadPrevPage() return self:changeKeyPage(-1) end
function LibbyCatalog:onDpadNextPage() return self:changeKeyPage(1) end

function LibbyCatalog:onDpadPress()
    if self:revealKeyFocus() then return true end
    if self.detail_visible then
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

    local loan = self:focusedKeyItem() or self:selectedItem()
    if loan then
                self.detail_visible = true
        self.selected_loan_id = itemKey(loan)
        self.key_detail_action_index = 1
        self:updateItems()
    end
    return true
end

function LibbyCatalog:onDpadBack()
    if self.detail_visible then
        self.detail_visible = false
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

function LibbyCatalog:onDpadMenu()
    if self.settings_callback then self.settings_callback() end
    return true
end

function LibbyCatalog:itemsForSelectedScope()
    if MediaRacks.is_synthetic(self.selected_scope_id) then
        return MediaRacks.items(self.snapshot, self.selected_scope_id) or {}
    end
    local loans = type(self.snapshot.loans) == "table" and self.snapshot.loans or {}
    if self.holds_only then
        local holds = {}
        for _, loan in ipairs(loans) do
            if loan.on_hold == true then table.insert(holds, loan) end
        end
        loans = holds
    end
    if self.selected_scope_id == "__all__" then return loans end
    local filtered = {}
    for _, loan in ipairs(loans) do
        if tostring(loan.card_id or "") == tostring(self.selected_scope_id or "") then
            table.insert(filtered, loan)
        end
    end
    return filtered
end

function LibbyCatalog:selectedScopeInfo()
    local loans = self:itemsForSelectedScope()
    if self.selected_scope_id == MediaRacks.AUDIOBOOKS_SCOPE then
        return _("Audiobooks"), #loans
    end
    if self.selected_scope_id == MediaRacks.MAGAZINE_SCOPE then
        return _("Magazine Rack"), #loans
    end
    if self.selected_scope_id == MediaRacks.ALL_SCOPE then
        return _("All Libraries"), #loans
    end
    for _, card in ipairs(type(self.snapshot.cards) == "table" and self.snapshot.cards or {}) do
        if tostring(cardId(card) or "") == tostring(self.selected_scope_id or "") then
            return rawCardName(card), #loans
        end
    end
    local fallback = loans[1] and loans[1].library or _("Library")
    return tostring(fallback), #loans
end

function LibbyCatalog:cycleBrowserScope()
    local cards = type(self.snapshot.cards) == "table" and self.snapshot.cards or {}
    local scopes = MediaRacks.scope_ids(cards, self.snapshot)

    local current = tostring(self.selected_scope_id or "__all__")
    local current_index
    for index, id in ipairs(scopes) do
        if tostring(id) == current then
            current_index = index
            break
        end
    end
    local next_index = current_index and (current_index % #scopes + 1) or 1
    self:selectScope(scopes[next_index], self.key_focus_active and self.key_focus_region == "header")
end

function LibbyCatalog:browserPageCount()
    local per_page = self.browser_view_mode == "list"
        and self.browser_list_rows
        or math.max(1, self.browser_grid_columns * self.browser_grid_rows)
    return math.max(1, math.ceil(#self:itemsForSelectedScope() / math.max(1, per_page)))
end

function LibbyCatalog:browserPage()
    return self.browser_view_mode == "list" and self.browser_list_page or self.browser_grid_page
end

function LibbyCatalog:setBrowserPage(page)
    local count = self:browserPageCount()
    local next_page = math.max(1, math.min(count, tonumber(page) or 1))
    if self.browser_view_mode == "list" then
        self.browser_list_page = next_page
    else
        self.browser_grid_page = next_page
    end
    self:updateItems()
end

function LibbyCatalog:toggleBrowserView()
    self.browser_view_mode = self.browser_view_mode == "grid" and "list" or "grid"
    self.settings.libby_browser_view_mode = self.browser_view_mode
    self.browser_grid_page = 1
    self.browser_list_page = 1
    self.detail_visible = false
    if self.selection_changed_callback then self.selection_changed_callback() end
    self:updateItems()
end

function LibbyCatalog:toggleBrowserHolds()
    self.holds_only = not self.holds_only
    self.detail_visible = false
    self.selected_loan_id = nil
    self.browser_grid_page = 1
    self.browser_list_page = 1
    if self.selection_changed_callback then self.selection_changed_callback() end
    self:updateItems()
end

function LibbyCatalog:showDetail(loan)
    self.key_focus_active = false
    self.key_focus_index = nil
    if loan and loan.media_type == "magazine" and loan.magazine_new_issue == true then
        local acknowledged = self.magazine_acknowledge_callback and self.magazine_acknowledge_callback(loan) or false
        if acknowledged == true then
            loan.magazine_new_issue = false
            for _, magazine in ipairs(type(self.snapshot.magazine_subscriptions) == "table" and self.snapshot.magazine_subscriptions or {}) do
                if tostring(magazine.id or "") == tostring(loan.id or "") then magazine.magazine_new_issue = false end
            end
        end
    end
    self.selected_loan_id = itemKey(loan)
    self.detail_visible = true
    self:updateItems()
end

function LibbyCatalog:hideDetail()
    self.detail_visible = false
    self:updateItems()
end

function LibbyCatalog:setBrowserLayout(columns, rows, list_rows)
    self.browser_grid_columns = math.max(2, math.min(8, tonumber(columns) or 4))
    self.browser_grid_rows = math.max(1, math.min(6, tonumber(rows) or 3))
    self.browser_list_rows = math.max(4, math.min(12, tonumber(list_rows) or 7))
    self.settings.libby_browser_grid_columns = self.browser_grid_columns
    self.settings.libby_browser_grid_rows = self.browser_grid_rows
    self.settings.libby_browser_list_rows = self.browser_list_rows
    local loan_count = #self:itemsForSelectedScope()
    local grid_pages = math.max(1, math.ceil(loan_count / math.max(1, self.browser_grid_columns * self.browser_grid_rows)))
    local list_pages = math.max(1, math.ceil(loan_count / math.max(1, self.browser_list_rows)))
    self.browser_grid_page = math.min(self.browser_grid_page, grid_pages)
    self.browser_list_page = math.min(self.browser_list_page, list_pages)
    self:updateItems()
end

function LibbyCatalog:selectedItem()
    local loans = self:itemsForSelectedScope()
    if #loans == 0 then return nil end
    for _, loan in ipairs(loans) do
        if itemKey(loan) == tostring(self.selected_loan_id or "") then return loan end
    end
    self.selected_loan_id = itemKey(loans[1])
    return loans[1]
end

function LibbyCatalog:persistBrowserState()
    self.settings.libby_browser_scope_id = self.selected_scope_id or MediaRacks.ALL_SCOPE
    self.settings.libby_browser_view_mode = self.browser_view_mode
    if self.selection_changed_callback then self.selection_changed_callback() end
end

function LibbyCatalog:selectScope(id, preserve_header_focus)
    local keep_header = preserve_header_focus == true and self.key_focus_active and self.key_focus_region == "header"
    self.selected_scope_id = id or MediaRacks.ALL_SCOPE
    self.selected_loan_id = nil
    self.detail_visible = false
    self.holds_only = false
    self.browser_grid_page = 1
    self.browser_list_page = 1
    self:persistBrowserState()
    if keep_header then
        self.key_focus_active = true
        self.key_focus_region = "header"
        self.key_focus_index = nil
    elseif not Dpad.is_touch_device(Device) then
        self.key_focus_active = true
        self.key_focus_region = "books"
        self.key_focus_index = Dpad.first_index_for_page(1, self:keyFocusPerPage(), #self:itemsForSelectedScope())
        if not self.key_focus_index then self.key_focus_region = "header" end
    else
        self.key_focus_active = false
        self.key_focus_region = nil
        self.key_focus_index = nil
    end
    self:updateItems()
end

function LibbyCatalog:onBrowserSwipeNext()
    if not self.detail_visible then self:setBrowserPage(self:browserPage() + 1) end
    return true
end

function LibbyCatalog:onBrowserSwipePrev()
    if not self.detail_visible then self:setBrowserPage(self:browserPage() - 1) end
    return true
end

function LibbyCatalog:browserHeaderWidget(width, height)
    local scope_name, item_count = self:selectedScopeInfo()
    local icon_w = height
    local title_w = math.max(1, width - 6 * icon_w)
    local title_text_w = math.max(1, title_w - Screen:scaleBySize(12))
    local icon_size = math.min(Screen:scaleBySize(26), math.max(1, height - Screen:scaleBySize(10)))
    local title_text, title_face = fitBrowserHeaderText(
        scope_name, item_count, title_text_w, self.refresh_state == "refreshing"
    )

    local row = HorizontalGroup:new{ align = "center" }
    table.insert(row, iconTap(SWAP_ICON_PATH or "cre.render.reload", icon_w, height, function()
        self:cycleBrowserScope()
    end, icon_size, nil, self:isKeyHeaderActionFocused(1)))
    table.insert(row, CenterContainer:new{
        dimen = Geom:new{ w = title_w, h = height },
        TextWidget:new{
            text = title_text,
            face = title_face,
            bold = true,
            max_width = title_text_w,
        },
    })
    if MediaRacks.is_synthetic(self.selected_scope_id) then
        table.insert(row, HorizontalSpan:new{ width = icon_w })
    else
        table.insert(row, CenterContainer:new{
            dimen = Geom:new{ w = icon_w, h = height },
            filterIconTap(HOLDS_ICON_PATH or "bookmark", icon_w, height, self.holds_only, function()
                self:toggleBrowserHolds()
            end, icon_size, self:isKeyHeaderActionFocused(2)),
        })
    end
    table.insert(row, iconTap(REFRESH_ICON_PATH or "cre.render.reload", icon_w, height, function()
        if self.refresh_state ~= "refreshing" and self.refresh_callback then self.refresh_callback() end
    end, icon_size, nil, self:isKeyHeaderActionFocused(3)))
    table.insert(row, iconTap(SETTINGS_ICON_PATH or "appbar.settings", icon_w, height, function()
        if self.settings_callback then self.settings_callback() end
    end, icon_size, nil, self:isKeyHeaderActionFocused(4)))
    local toggle_icon = self.browser_view_mode == "grid" and (LIST_ICON_PATH or "appbar.menu") or (GRID_ICON_PATH or "column.two")
    table.insert(row, iconTap(toggle_icon, icon_w, height, function() self:toggleBrowserView() end,
        icon_size, nil, self:isKeyHeaderActionFocused(5)))
    table.insert(row, iconTap(CLOSE_ICON_PATH or "close", icon_w, height, function()
        if self.close_callback then self.close_callback() else UIManager:close(self) end
    end, icon_size, nil, self:isKeyHeaderActionFocused(6)))
    return FrameContainer:new{
        width = width, height = height, margin = 0, padding = 0,
        bordersize = Size.border.thin, background = Blitbuffer.COLOR_WHITE,
        row,
    }
end

function LibbyCatalog:browserGridWidget(width, height)
    local loans = self:itemsForSelectedScope()
    if #loans == 0 then
        return CenterContainer:new{
            dimen = Geom:new{ w = width, h = height },
            TextWidget:new{ text = _("No borrowed or held titles to display."), face = Font:getFace("infofont") },
        }
    end

    local gap = Screen:scaleBySize(8)
    local label_h = Screen:scaleBySize(22)
    local cols = self.browser_grid_columns
    local rows = self.browser_grid_rows
    local per_page = math.max(1, cols * rows)
    local first, last, pages = Dpad.page_bounds(self.browser_grid_page, per_page, #loans)
    self.browser_grid_page = math.max(1, math.min(self.browser_grid_page, pages))
    local cell_w = math.max(1, math.floor((width - (cols + 1) * gap) / cols))

    local function bookCell(loan, cell_h)
        local cover_area_h = math.max(1, cell_h - label_h)
        local cover_w = math.max(1, math.min(cell_w, math.floor(cover_area_h / 1.5)))
        local cover_h = math.max(1, math.min(cover_area_h, math.floor(cover_w * 1.5)))
        local path = self.cover_path_callback and self.cover_path_callback(loan) or nil
        local card = VerticalGroup:new{ align = "center" }
        table.insert(card, coverWidget(loan, cover_w, cover_h, path, false, self:isKeyFocusedItem(loan)))
        table.insert(card, CenterContainer:new{
            dimen = Geom:new{ w = cell_w, h = label_h },
            colorAwareTextWidget{
                text = self:coverStatusText(loan),
                face = Font:getFace("cfont", 14),
                fgcolor = loanTimeColor(loan),
                bold = true,
                max_width = cell_w,
                height = label_h,
                alignment = "center",
            },
        })
        return tappableWidget(
            CenterContainer:new{ dimen = Geom:new{ w = cell_w, h = cell_h }, card },
            cell_w,
            cell_h,
            function() self:showDetail(loan) end
        )
    end

    if not MediaRacks.is_synthetic(self.selected_scope_id) then
        local cell_h = math.max(1, math.floor((height - (rows + 1) * gap) / rows))
        local grid = VerticalGroup:new{ align = "center" }
        local index = first
        for _ = 1, rows do
            table.insert(grid, VerticalSpan:new{ width = gap })
            local row = HorizontalGroup:new{ align = "center" }
            table.insert(row, HorizontalSpan:new{ width = gap })
            for _ = 1, cols do
                local loan = loans[index]
                if loan and index <= last then
                    table.insert(row, bookCell(loan, cell_h))
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

    local positions, book_rows, groups = MediaRacks.grid_positions(loans, first, last, cols)
    local group_h = Screen:scaleBySize(24)
    local total_gap_h = (#groups + math.max(1, book_rows) + 1) * gap
    local available_book_h = math.max(1, height - #groups * group_h - total_gap_h)
    local cell_h = math.max(1, math.floor(available_book_h / math.max(1, book_rows)))
    local grid = VerticalGroup:new{ align = "center" }
    for _, group in ipairs(groups) do
        table.insert(grid, VerticalSpan:new{ width = gap })
        table.insert(grid, rackGroupHeaderWidget(group.key, group.count, width, group_h))
        local entry_index = 1
        while entry_index <= #group.entries do
            table.insert(grid, VerticalSpan:new{ width = gap })
            local row = HorizontalGroup:new{ align = "center" }
            table.insert(row, HorizontalSpan:new{ width = gap })
            for _ = 1, cols do
                local entry = group.entries[entry_index]
                if entry then
                    table.insert(row, bookCell(entry.item, cell_h))
                    entry_index = entry_index + 1
                else
                    table.insert(row, HorizontalSpan:new{ width = cell_w })
                end
                table.insert(row, HorizontalSpan:new{ width = gap })
            end
            table.insert(grid, row)
        end
    end
    self.browser_grid_positions = positions
    return grid
end

function LibbyCatalog:browserListWidget(width, height)
    local loans = self:itemsForSelectedScope()
    if #loans == 0 then
        return CenterContainer:new{
            dimen = Geom:new{ w = width, h = height },
            TextWidget:new{ text = _("No borrowed or held titles to display."), face = Font:getFace("infofont") },
        }
    end

    local rows = self.browser_list_rows
    local first, last, pages = Dpad.page_bounds(self.browser_list_page, rows, #loans)
    self.browser_list_page = math.max(1, math.min(self.browser_list_page, pages))
    local pad = Screen:scaleBySize(5)
    local status_face = Font:getFace("cfont", 15)
    local status_probe = TextWidget:new{ text = "#1000 in line · 365 days", face = status_face, bold = true }
    local desired_loan_w = status_probe:getSize().w + 2 * pad
    for _, candidate in ipairs(loans) do
        local candidate_probe = TextWidget:new{ text = self:coverStatusText(candidate), face = status_face, bold = true }
        desired_loan_w = math.max(desired_loan_w, candidate_probe:getSize().w + 2 * pad)
    end
    local loan_w = math.min(desired_loan_w, math.floor(width * 0.40))
    local synthetic = MediaRacks.is_synthetic(self.selected_scope_id)
    local groups = synthetic and MediaRacks.page_groups(loans, first, last) or nil
    local group_h = synthetic and Screen:scaleBySize(24) or 0
    local row_h = math.max(1, math.floor((height - (synthetic and #groups * group_h or 0)) / rows))
    local list = VerticalGroup:new{ align = "center" }

    local function appendRow(loan)
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
        local secondary_text
        if loan.media_type == "magazine" then
            secondary_text = safeText(loan.edition or loan.publish_date, 90)
        else
            secondary_text = safeText(loan.author, 90)
            if secondary_text:lower() == "n/a" then secondary_text = "" end
        end
        if secondary_text ~= "" then
            table.insert(meta, TextWidget:new{
                text = secondary_text,
                face = Font:getFace("smallinfofont", 14),
                max_width = meta_w,
            })
        end
        if not synthetic then
            local fallback_library = self:selectedScopeInfo()
            table.insert(meta, TextWidget:new{
                text = tostring(loan.library or fallback_library),
                face = Font:getFace("smallinfofont", 13),
                max_width = meta_w,
            })
        end

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
                text = self:coverStatusText(loan),
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
            bordersize = self:isKeyFocusedItem(loan) and math.max(Size.border.default, Screen:scaleBySize(3)) or Size.border.thin,
            color = Blitbuffer.COLOR_BLACK, background = Blitbuffer.COLOR_WHITE,
            row_content,
        }
        table.insert(list, tappableWidget(frame, width, row_h, function() self:showDetail(loan) end))
    end

    if synthetic then
        for _, group in ipairs(groups) do
            table.insert(list, rackGroupHeaderWidget(group.key, group.count, width, group_h))
            for _, entry in ipairs(group.entries) do appendRow(entry.item) end
        end
        local visible = last >= first and (last - first + 1) or 0
        for _ = visible + 1, rows do table.insert(list, VerticalSpan:new{ width = row_h }) end
    else
        for index = first, first + rows - 1 do
            local loan = index <= last and loans[index] or nil
            if loan then appendRow(loan) else table.insert(list, VerticalSpan:new{ width = row_h }) end
        end
    end
    return list
end

function LibbyCatalog:browserPaginationWidget(width, height)
    local pages = self:browserPageCount()
    local current = math.max(1, math.min(self:browserPage(), pages))
    local can_back = current > 1
    local can_forward = current < pages
    local nav_w = math.floor(width * 0.75)
    local icon_size = math.floor(height * 0.62)
    local function slot(ratio) return math.max(1, math.floor(nav_w * ratio)) end
    local first = Button:new{
        icon = "chevron.first", icon_width = icon_size, icon_height = icon_size,
        width = slot(0.18), enabled = can_back, callback = function() self:setBrowserPage(1) end,
        margin = 0, bordersize = 0, show_parent = self,
    }
    local prev = Button:new{
        icon = "chevron.left", icon_width = icon_size, icon_height = icon_size,
        width = slot(0.18), enabled = can_back, callback = function() self:setBrowserPage(current - 1) end,
        margin = 0, bordersize = 0, show_parent = self,
    }
    local page = Button:new{
        text = string.format(_("Page %d of %d"), current, pages),
        text_font_face = "cfont", text_font_size = 15,
        width = slot(0.28), margin = 0, bordersize = 0, show_parent = self,
    }
    local next_btn = Button:new{
        icon = "chevron.right", icon_width = icon_size, icon_height = icon_size,
        width = slot(0.18), enabled = can_forward, callback = function() self:setBrowserPage(current + 1) end,
        margin = 0, bordersize = 0, show_parent = self,
    }
    local last = Button:new{
        icon = "chevron.last", icon_width = icon_size, icon_height = icon_size,
        width = slot(0.18), enabled = can_forward, callback = function() self:setBrowserPage(pages) end,
        margin = 0, bordersize = 0, show_parent = self,
    }
    return CenterContainer:new{
        dimen = Geom:new{ w = width, h = height },
        HorizontalGroup:new{ align = "center", first, prev, page, next_btn, last },
    }
end

function LibbyCatalog:detailWidget(width, height, tall_portrait, cover_reference_height)
    local loan = self:selectedItem()
    if not loan then return nil end

    local pad = Size.padding.default
    local top_inset = math.max(5, Screen:scaleBySize(5))
    local cover_top_inset = math.max(1, Screen:scaleBySize(1))
    local action_h = Screen:scaleBySize(34)
    local gap = Screen:scaleBySize(8)
    local on_hold = loan.on_hold == true
    local hold_borrowable = on_hold and holdBorrowable(loan)
    local show_return = self.return_enabled == true and loan.extended_loan ~= true and not on_hold
        and loan.magazine_subscription ~= true
    local show_delete = loan.extended_loan == true
    -- Every detail card includes Book Notes immediately before Close.
    local button_count = on_hold and (hold_borrowable and 4 or 3) or ((show_return or show_delete) and 4 or 3)
    local geometry = CatalogLayout.detailGeometry(
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
        local reference_geometry = CatalogLayout.detailGeometry(
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
    if loan.media_type == "magazine" then
        if loan.edition then table.insert(detail_rows, { _("Edition: "), safeText(loan.edition, 60) }) end
        if loan.magazine_frequency then table.insert(detail_rows, { _("Frequency: "), safeText(loan.magazine_frequency, 40) }) end
        if loan.publish_date then table.insert(detail_rows, { _("Published: "), safeText(loan.publish_date, 40) }) end
    end
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
    elseif loan.magazine_subscription == true then
        insertCompactDetailRow(metadata, _("Status: "), _("Current subscription issue"), Blitbuffer.COLOR_BLACK, false)
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
    elseif loan.media_type == "audiobook" or loan.media_type == "magazine" then
        action = actionButton(_("Libby Info"), button_w, action_h, true, function()
            if self.libby_media_callback then self.libby_media_callback(loan) end
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
        self:hideDetail()
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

function LibbyCatalog:detailLayer(modal_width, modal_height, tall_portrait, cover_reference_height)
    local detail = self:detailWidget(modal_width, modal_height, tall_portrait, cover_reference_height)
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
        TapDismissDetail = { GestureRange:new{ ges = "tap", range = layer.dimen } },
    }
    layer.onTapDismissDetail = function(_, ges)
        if ges and ges.pos and ges.pos:notIntersectWith(modal_rect) then
            self:hideDetail()
        end
        return true
    end
    return layer
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
    local header_height = Screen:scaleBySize(42)
    local content_height = math.max(Screen:scaleBySize(100), self.height - header_height - footer_height)
    local shelf = self.browser_view_mode == "list"
        and self:browserListWidget(self.width, content_height)
        or self:browserGridWidget(self.width, content_height)
    local content = VerticalGroup:new{
        align = "center",
        self:browserHeaderWidget(self.width, header_height),
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
    local overlap = TopFirstOverlapGroup:new{
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
            self:browserPaginationWidget(self.width, footer_height),
        },
    }
    if self.detail_visible and self:selectedItem() then
        local modal = CatalogLayout.browserModalGeometry(
            self.width,
            self.height,
            function(value) return Screen:scaleBySize(value) end
        )
        local cover_reference_height = modal.height
        overlap[#overlap + 1] = self:detailLayer(modal.width, modal.height, modal.tall, cover_reference_height)
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
    self.detail_visible = false

    local valid = false
    for _, scope_id in ipairs(MediaRacks.scope_ids(self.snapshot.cards, self.snapshot)) do
        if tostring(scope_id) == tostring(self.selected_scope_id) then
            valid = true
            break
        end
    end
    if not valid then
        self.selected_scope_id = MediaRacks.ALL_SCOPE
        self:persistBrowserState()
    end

    local items = self:itemsForSelectedScope()
    if self.key_focus_waiting_for_items and #items > 0 then
        self.key_focus_waiting_for_items = false
        self.key_focus_region = "books"
        self.key_focus_index = Dpad.first_index_for_page(1, self:keyFocusPerPage(), #items)
    end
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
