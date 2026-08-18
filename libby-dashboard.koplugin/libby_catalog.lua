local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
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
local RenderImage = require("ui/renderimage")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")

local Screen = Device.screen

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

local function actionButton(text, width, height, available, callback)
    local bg = available and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_LIGHT_GRAY
    local fg = available and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_DARK_GRAY
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
        bordersize = 0,
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

local function iconTap(icon, width, height, callback, icon_size, tap_extend_left)
    local size = icon_size or math.floor(height * 0.62)
    local item = InputContainer:new{
        dimen = Geom:new{ w = width, h = height },
        CenterContainer:new{
            dimen = Geom:new{ w = width, h = height },
            IconWidget:new{ icon = icon, width = size, height = size },
        },
    }
    local tap_range = tap_extend_left and Geom:new{ x = -width, y = 0, w = width * 2, h = height } or item.dimen
    item.ges_events = { TapSelect = { GestureRange:new{ ges = "tap", range = tap_range } } }
    item.onTapSelect = function()
        if callback then callback() end
        return true
    end
    return item
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
    cover_path = nil,
    callback = nil,
}

local function safeText(value, max_len)
    local text = tostring(value or ""):gsub("[%z\1-\31\127]", " "):gsub("%s+", " ")
    if #text <= (max_len or 96) then return text end
    return text:sub(1, math.max(1, (max_len or 96) - 3)) .. "..."
end

local function outlinedLabel(text, width, height)
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
        bordersize = Size.border.thin,
        background = Blitbuffer.COLOR_WHITE,
        radius = Size.radius.button,
        CenterContainer:new{ dimen = Geom:new{ w = width, h = height }, label },
    }
end

local function mediaLabel(loan)
    if loan.media_type == "audiobook" then return _("Audiobook") end
    if loan.media_type == "magazine" then return _("Magazine") end
    if loan.media_type == "comic" then return _("Manga/Comic") end
    if loan.adobe_format and loan.adobe_format:find("pdf", 1, true) then return _("PDF") end
    if loan.adobe_format then return _("EPUB") end
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

local function coverWidget(loan, width, height, path, selected)
    local border = selected and Size.border.default or Size.border.thin
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
    if selected then cover.bordersize = Size.border.default end
    return cover
end

function CoverCard:init()
    self.ges_events = {
        TapSelect = { GestureRange:new{ ges = "tap", range = self.dimen } },
    }
    local loan = self.loan or {}
    self[1] = coverWidget(loan, self.dimen.w, self.dimen.h, self.cover_path, self.selected)
end

function CoverCard:onTapSelect()
    if self.callback then self.callback(self.loan) end
    return true
end

local function cardId(card)
    return card and (card.id or card.cardId)
end

local function cardName(card)
    return safeText(card and (card.name or card.libraryName or card.id) or _("Library"), 30)
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
    self.ges_events = {
        SwipeShelfNext = { GestureRange:new{ ges = "swipe", range = self.dimen, direction = "west" } },
        SwipeShelfPrev = { GestureRange:new{ ges = "swipe", range = self.dimen, direction = "east" } },
    }
    self:updateItems()
end

function LibbyCatalog:loansForSelectedCard()
    local loans = type(self.snapshot.loans) == "table" and self.snapshot.loans or {}
    if self.selected_card_id == "__all__" then return loans end
    local filtered = {}
    for _, loan in ipairs(loans) do
        if tostring(loan.card_id or "") == tostring(self.selected_card_id or "") then
            table.insert(filtered, loan)
        end
    end
    return filtered
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
    self.selected_loan_id = loanKey(loan)
    self:persistSelection()
    self:updateItems()
end

function LibbyCatalog:selectCard(id)
    self.selected_card_id = id or "__all__"
    self.selected_loan_id = nil
    self.shelf_page = 1
    self.settings.libby_shelf_page = 1
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
    self:gotoShelfPage(self.shelf_page + 1)
    return true
end

function LibbyCatalog:onSwipeShelfPrev()
    self:gotoShelfPage(self.shelf_page - 1)
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
            TextWidget:new{ text = _("No loans in this library."), face = Font:getFace("infofont") },
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
        { label = _("Expires On: "), value = loan.days_remaining ~= nil and (tostring(loan.days_remaining) .. _(" days left")) or _("N/A") },
    }
    for _, row in ipairs(metadata_rows) do
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
            TextWidget:new{
                text = row.value,
                bold = true,
                face = metadata_face,
                max_width = value_w,
                forced_height = row_h,
            },
        })
    end

    local action_text
    local downloadable = loan.adobe_format ~= nil
    local downloaded_path = self.downloaded_path_callback and self.downloaded_path_callback(loan) or nil
    local locally_available = type(downloaded_path) == "string" and downloaded_path ~= ""
    local network_ok = self.network_available_callback == nil or self.network_available_callback()
    if locally_available then
        action_text = _("Open")
    elseif loan.media_type == "audiobook" or loan.media_type == "magazine" or not loan.adobe_format then
        action_text = _("Unsupported")
        downloadable = false
    else
        action_text = _("Download")
    end

    local action_h = Screen:scaleBySize(34)
    local show_return = self.return_enabled == true
    local min_gap = Screen:scaleBySize(8)
    local button_w = show_return
        and math.max(1, math.floor((text_w - min_gap) / 2))
        or math.min(text_w, Screen:scaleBySize(150))
    local action
    if locally_available then
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
    if show_return then
        local return_action = actionButton(_("Return"), button_w, action_h, network_ok, function()
            if self.return_callback then self.return_callback(loan) end
        end)
        action_row = HorizontalGroup:new{
            align = "center",
            action,
            HorizontalSpan:new{ width = math.max(min_gap, text_w - 2 * button_w) },
            return_action,
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
    local middle_w = math.max(1, width - 2 * button_w)
    local chrome_icon = math.min(Screen:scaleBySize(32), math.max(1, height - Screen:scaleBySize(8)))
    local refresh_icon = math.min(Screen:scaleBySize(26), math.max(1, height - Screen:scaleBySize(12)))
    local row = HorizontalGroup:new{ align = "center" }
    table.insert(row, hamburgerTap(button_w, height, function()
        if self.settings_callback then self.settings_callback() end
    end))

    local center = HorizontalGroup:new{ align = "center" }
    table.insert(center, TextWidget:new{
        text = _("Libby Dashboard") .. " (" .. refreshAgeText(self.snapshot, self.refresh_state) .. ")",
        face = Font:getFace("cfont", 18),
        bold = true,
        max_width = math.max(1, middle_w - height - Screen:scaleBySize(8)),
    })
    table.insert(center, HorizontalSpan:new{ width = Screen:scaleBySize(6) })
    table.insert(center, iconTap("cre.render.reload", height, height, function()
        if self.refresh_state ~= "refreshing" and self.refresh_callback then self.refresh_callback() end
    end, refresh_icon))
    table.insert(row, CenterContainer:new{ dimen = Geom:new{ w = middle_w, h = height }, center })
    table.insert(row, iconTap("close", button_w, height, function()
        if self.close_callback then self.close_callback() else UIManager:close(self) end
    end, chrome_icon))
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

    local label_h = Screen:scaleBySize(24)
    local tabs_h = math.max(1, height - label_h)
    local label = FrameContainer:new{
        width = width, height = label_h, margin = 0, padding = 0,
        bordersize = Size.border.thin, background = Blitbuffer.COLOR_WHITE, radius = 0,
        CenterContainer:new{
            dimen = Geom:new{ w = width, h = label_h },
            TextWidget:new{ text = _("Libraries"), face = Font:getFace("cfont", 17), bold = true },
        },
    }
    local row = HorizontalGroup:new{ align = "center" }
    local count = math.max(1, #tabs)
    local tab_w = math.floor((width - 2 * Size.border.thin) / count)
    for _, tab in ipairs(tabs) do
        local selected = tostring(self.selected_card_id) == tostring(tab.id)
        table.insert(row, tappableFrame(
            safeText(tab.name, 13) .. " (" .. tostring(tab.count) .. ")",
            tab_w,
            tabs_h,
            selected,
            function() self:selectCard(tab.id) end,
            17
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
            TextWidget:new{ text = _("No borrowed titles to display."), face = Font:getFace("infofont") },
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
    local cover_w = math.max(1, cell_w)
    local cover_h = math.max(1, math.min(cell_h, math.floor(cover_w * 1.5)))
    if cover_h < math.floor(cover_w * 1.5) then
        cover_w = math.max(1, math.floor(cover_h / 1.5))
    end
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
                table.insert(row, CenterContainer:new{
                    dimen = Geom:new{ w = cell_w, h = cell_h },
                    CoverCard:new{
                        loan = loan,
                        dimen = Geom:new{ w = cover_w, h = cover_h },
                        selected = loanKey(loan) == tostring(self.selected_loan_id or ""),
                        cover_path = path,
                        callback = function(selected_loan) self:selectLoan(selected_loan) end,
                    },
                })
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
    self.width = Screen:getWidth()
    self.height = Screen:getHeight()
    if self.dimen then
        self.dimen.w = self.width
        self.dimen.h = self.height
    else
        self.dimen = Geom:new{ w = self.width, h = self.height }
    end

    local header_height = Screen:scaleBySize(40)
    local top_height = math.floor(self.height * 0.30)
    local tabs_height = Screen:scaleBySize(56)
    local footer_height = Screen:scaleBySize(32)
        + 2 * Screen:scaleBySize(4)
        + Screen:scaleBySize(12)
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
    local overlap = OverlapGroup:new{
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

    if self[1] and self[1].free then self[1]:free() end
    self[1] = overlap

    UIManager:setDirty(self, function()
        return "ui", self.dimen
    end)
end

function LibbyCatalog:refreshSnapshot(snapshot, state)
    self.snapshot = snapshot or {}
    self.refresh_state = state
    self.selected_loan_id = nil
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
