local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local CheckButton = require("ui/widget/checkbutton")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local Dpad = require("libby_dpad")
local PathTemplate = require("path_template")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TopContainer = require("ui/widget/container/topcontainer")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")

local SettingsDialog = {}

local function copyState(state)
    return {
        grid_columns = state.grid_columns,
        grid_rows = state.grid_rows,
        list_rows = state.list_rows,
    }
end

local function sameState(a, b)
    return a.grid_columns == b.grid_columns
        and a.grid_rows == b.grid_rows
        and a.list_rows == b.list_rows
end

local function currentState(plugin)
    local settings = plugin.controller.settings
    return {
        grid_columns = math.max(2, math.min(8, tonumber(settings.libby_browser_grid_columns) or 4)),
        grid_rows = math.max(1, math.min(6, tonumber(settings.libby_browser_grid_rows) or 3)),
        list_rows = math.max(4, math.min(12, tonumber(settings.libby_browser_list_rows) or 7)),
    }
end

local function preview(plugin, state)
    local settings = plugin.controller.settings
    if plugin.catalog_browser and UIManager:isWidgetShown(plugin.catalog_browser) then
        plugin.catalog_browser:setBrowserLayout(state.grid_columns, state.grid_rows, state.list_rows)
    else
        settings.libby_browser_grid_columns = state.grid_columns
        settings.libby_browser_grid_rows = state.grid_rows
        settings.libby_browser_list_rows = state.list_rows
    end
end

function SettingsDialog.show(plugin, section, original, values, focus_state)
    section = section or "general"
    original = original or currentState(plugin)
    values = values or copyState(original)
    focus_state = type(focus_state) == "table" and focus_state or {}

    local focus_visible = focus_state.visible
    if focus_visible == nil then focus_visible = not Dpad.is_touch_device(Device) end
    local focus_zone = focus_state.zone or "nav"
    local focused_nav_index = math.max(1, tonumber(focus_state.nav_index) or 1)
    local focused_content_index = math.max(1, tonumber(focus_state.content_index) or 1)
    local content_actions = {}
    local nav_actions = {}

    local screen = Device.screen:getSize()
    local scale = function(n) return Device.screen:scaleBySize(n) end
    local border = Size.border.thin
    local shell_border = Size.border.default
    local divider_w = math.max(1, border)
    local dialog_w = math.max(1, screen.w - math.max(scale(18), math.floor(screen.w * 0.07)))
    local header_h = scale(30)
    local desired_body_h = scale(304)
    local max_dialog_h = math.max(1, screen.h - math.max(scale(24), math.floor(screen.h * 0.12)))
    local dialog_h = math.min(max_dialog_h, header_h + desired_body_h + 2 * shell_border)
    local dialog_inner_w = math.max(1, dialog_w - 2 * shell_border)
    local dialog_inner_h = math.max(1, dialog_h - 2 * shell_border)
    local body_h = math.max(1, dialog_inner_h - header_h)
    local nav_w = math.max(scale(112), math.floor(dialog_inner_w * 0.27))
    nav_w = math.min(math.floor(dialog_inner_w * 0.33), nav_w)
    local content_w = math.max(1, dialog_inner_w - nav_w - divider_w)
    local page_pad = math.max(scale(7), math.floor(content_w * 0.025))
    local content_inner_w = math.max(1, content_w - 2 * page_pad)
    local dialog

    local function closeDialog()
        if dialog then UIManager:close(dialog) end
        if plugin.settings_dialog == dialog then plugin.settings_dialog = nil end
    end

    local function closeAndRevert()
        closeDialog()
        preview(plugin, original)
        plugin.controller:save()
    end

    local function tapFrame(text, width, height, opts, callback)
        opts = opts or {}
        local focus_index
        if callback and opts.navigation ~= false then
            table.insert(content_actions, callback)
            focus_index = #content_actions
        end
        local focused = opts.focused == true
            or (focus_visible and focus_zone == "content" and focus_index ~= nil and focus_index == focused_content_index)
        local pad = opts.pad or scale(6)
        local bordersize = focused and math.max(Size.border.default, scale(3)) or (opts.bordersize or 0)
        local frame_padding = opts.align == "left" and pad or 0
        local inner_w = math.max(1, width - 2 * (bordersize + frame_padding))
        local inner_h = math.max(1, height - 2 * (bordersize + frame_padding))
        local label = TextWidget:new{
            text = text,
            face = Font:getFace(opts.face or "cfont", opts.font_size or 15),
            bold = opts.bold == true,
            fgcolor = opts.fgcolor or Blitbuffer.COLOR_BLACK,
            max_width = inner_w,
        }
        local aligned
        if opts.align == "left" then
            aligned = LeftContainer:new{
                dimen = Geom:new{ w = inner_w, h = inner_h },
                label,
            }
        else
            aligned = CenterContainer:new{
                dimen = Geom:new{ w = inner_w, h = inner_h },
                label,
            }
        end
        local frame = FrameContainer:new{
            width = width,
            height = height,
            margin = 0,
            padding = frame_padding,
            bordersize = bordersize,
            background = opts.background or Blitbuffer.COLOR_WHITE,
            radius = opts.radius or 0,
            aligned,
        }
        local item = InputContainer:new{
            dimen = Geom:new{ w = width, h = height },
            frame,
        }
        item.ges_events = {
            TapSelect = { GestureRange:new{ ges = "tap", range = item.dimen } },
        }
        item.onTapSelect = function()
            if callback then callback() end
            return true
        end
        return item
    end

    local function currentFocusState()
        return {
            visible = focus_visible,
            zone = focus_zone,
            nav_index = focused_nav_index,
            content_index = focused_content_index,
        }
    end

    local function reopen(next_section, next_values, apply_preview, next_focus)
        closeDialog()
        if apply_preview and next_values then preview(plugin, next_values) end
        SettingsDialog.show(plugin, next_section or section, original, next_values or values, next_focus or currentFocusState())
    end

    local function redrawFocus()
        reopen(section, values, false, currentFocusState())
    end

    local function chooseNumber(title, key, minimum, maximum)
        local picker
        local rows = {}
        local row = {}
        for number = minimum, maximum do
            local selected_number = number
            local text = number == values[key] and ("[" .. tostring(number) .. "]") or tostring(number)
            table.insert(row, {
                text = text,
                callback = function()
                    UIManager:close(picker)
                    local next_values = copyState(values)
                    next_values[key] = selected_number
                    reopen(section, next_values, true)
                end,
            })
            if #row == 3 then
                table.insert(rows, row)
                row = {}
            end
        end
        if #row > 0 then table.insert(rows, row) end
        picker = ButtonDialog:new{
            title = title,
            title_align = "center",
            buttons = rows,
        }
        UIManager:show(picker)
    end

    local function selector(value, title, key, minimum, maximum, width, height)
        return tapFrame(tostring(value), width, height, {
            font_size = 14,
            bordersize = border,
            background = Blitbuffer.COLOR_WHITE,
        }, function()
            chooseNumber(title, key, minimum, maximum)
        end)
    end

    local function settingField(label_text, key, minimum, maximum, label_w, selector_w)
        local h = scale(30)
        return HorizontalGroup:new{
            align = "center",
            LeftContainer:new{
                dimen = Geom:new{ w = label_w, h = h },
                TextWidget:new{
                    text = label_text,
                    face = Font:getFace("smallinfofont", 13),
                    max_width = math.max(1, label_w - scale(4)),
                },
            },
            selector(values[key], label_text, key, minimum, maximum, selector_w, h),
        }
    end

    local function pageHeading(title, subtitle)
        local group = VerticalGroup:new{ align = "left" }
        table.insert(group, TextWidget:new{
            text = title,
            face = Font:getFace("cfont", 18),
            bold = true,
            max_width = content_inner_w,
        })
        if subtitle then
            table.insert(group, VerticalSpan:new{ width = scale(1) })
            table.insert(group, TextWidget:new{
                text = subtitle,
                face = Font:getFace("smallinfofont", 12),
                max_width = content_inner_w,
            })
        end
        return group
    end

    local function sectionHeading(text)
        return TextWidget:new{
            text = text,
            face = Font:getFace("cfont", 14),
            bold = true,
            max_width = content_inner_w,
        }
    end

    local function actionButton(text, width, callback, primary, enabled)
        enabled = enabled ~= false
        return tapFrame(text, width, scale(33), {
            font_size = 14,
            bold = true,
            bordersize = border,
            background = enabled and (primary and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE) or Blitbuffer.COLOR_LIGHT_GRAY,
            fgcolor = enabled and (primary and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK) or Blitbuffer.COLOR_DARK_GRAY,
            radius = scale(2),
        }, enabled and callback or nil)
    end

    local function shelfPage()
        local top = VerticalGroup:new{ align = "left" }
        table.insert(top, pageHeading(_("Shelf Size (Items per page)"), _("Choose how many items to display in each view.")))
        table.insert(top, VerticalSpan:new{ width = scale(4) })

        local selector_w = math.min(scale(54), math.max(scale(46), math.floor(content_inner_w * 0.13)))
        local first_label_w = math.max(scale(108), math.floor(content_inner_w * 0.34))
        local second_label_w = math.max(scale(46), math.floor(content_inner_w * 0.13))
        local field_gap = math.max(scale(28), math.floor(content_inner_w * 0.09))
        local row_w = first_label_w + selector_w + field_gap + second_label_w + selector_w
        if row_w > content_inner_w then
            field_gap = math.max(scale(14), field_gap - (row_w - content_inner_w))
        end

        table.insert(top, sectionHeading(_("Browser - Grid (Book Cards)")))
        table.insert(top, VerticalSpan:new{ width = scale(2) })
        table.insert(top, HorizontalGroup:new{
            align = "center",
            settingField(_("Columns:"), "grid_columns", 2, 8, first_label_w, selector_w),
            HorizontalSpan:new{ width = field_gap },
            settingField(_("Rows:"), "grid_rows", 1, 6, second_label_w, selector_w),
        })
        table.insert(top, VerticalSpan:new{ width = scale(6) })

        table.insert(top, sectionHeading(_("Browser - List (Book List)")))
        table.insert(top, VerticalSpan:new{ width = scale(2) })
        table.insert(top, settingField(_("Rows per page:"), "list_rows", 4, 12, first_label_w, selector_w))
        table.insert(top, VerticalSpan:new{ width = scale(6) })

        local footer_gap = math.max(scale(12), math.floor(content_inner_w * 0.035))
        local reset_w = math.max(scale(140), math.floor(content_inner_w * 0.40))
        local save_w = math.max(scale(82), math.floor(content_inner_w * 0.22))
        local save_enabled = not sameState(original, values)
        if reset_w + save_w + footer_gap > content_inner_w then
            reset_w = math.max(scale(132), math.floor((content_inner_w - footer_gap) * 0.62))
            save_w = math.max(1, content_inner_w - footer_gap - reset_w)
        end
        table.insert(top, CenterContainer:new{
            dimen = Geom:new{ w = content_inner_w, h = scale(33) },
            HorizontalGroup:new{
                align = "center",
                actionButton(_("Reset to Defaults"), reset_w, function()
                    reopen("library", {
                        grid_columns = 4,
                        grid_rows = 3,
                        list_rows = 7,
                    }, true)
                end, false),
                HorizontalSpan:new{ width = footer_gap },
                actionButton(_("Save"), save_w, function()
                    preview(plugin, values)
                    plugin.controller:save()
                    local saved = copyState(values)
                    closeDialog()
                    SettingsDialog.show(plugin, "library", saved, copyState(saved))
                end, true, save_enabled),
            },
        })

        return TopContainer:new{
            dimen = Geom:new{ w = content_w, h = body_h },
            FrameContainer:new{
                width = content_w,
                height = body_h,
                margin = 0,
                padding = 0,
                padding_top = scale(4),
                padding_bottom = scale(4),
                padding_left = page_pad,
                padding_right = page_pad,
                bordersize = 0,
                background = Blitbuffer.COLOR_WHITE,
                top,
            },
        }
    end

    local function simplePage(title, subtitle, buttons)
        local group = VerticalGroup:new{ align = "left" }
        table.insert(group, pageHeading(title, subtitle))
        table.insert(group, VerticalSpan:new{ width = scale(18) })
        local button_w = math.min(content_inner_w, math.max(scale(180), math.floor(content_inner_w * 0.72)))
        for index, item in ipairs(buttons or {}) do
            table.insert(group, actionButton(item.text, button_w, item.callback, item.primary))
            if index < #(buttons or {}) then
                table.insert(group, VerticalSpan:new{ width = scale(8) })
            end
        end
        if not buttons or #buttons == 0 then
            table.insert(group, TextWidget:new{
                text = _("No settings in this section yet."),
                face = Font:getFace("smallinfofont", 14),
                max_width = content_inner_w,
            })
        end
        return TopContainer:new{
            dimen = Geom:new{ w = content_w, h = body_h },
            FrameContainer:new{
                width = content_w,
                height = body_h,
                margin = 0,
                padding = page_pad,
                bordersize = 0,
                background = Blitbuffer.COLOR_WHITE,
                group,
            },
        }
    end

    local function downloadsPage()
        local group = VerticalGroup:new{ align = "left" }
        table.insert(group, pageHeading(_("Downloads"), _("Configure download and storage behavior.")))
        table.insert(group, VerticalSpan:new{ width = scale(2) })

        local extended_check
        local extended_focus_index = #content_actions + 1
        local function applyExtendedLoanTime(value)
            plugin.controller:set_extended_loan_time(value == true)
            plugin:refreshCatalogFromCache()
            reopen("downloads", values, false)
        end
        table.insert(content_actions, function()
            applyExtendedLoanTime(not (extended_check and extended_check.checked == true))
        end)
        extended_check = CheckButton:new{
            text = _("Extended Loan Time"),
            checked = plugin.controller.settings.extended_loan_time == true,
            width = math.max(1, content_inner_w - 2 * math.max(Size.border.default, scale(3))),
            parent = group,
            face = Font:getFace("cfont", 13),
            single_line = true,
            callback = function()
                applyExtendedLoanTime(extended_check.checked)
            end,
        }
        table.insert(group, FrameContainer:new{
            width = content_inner_w,
            margin = 0,
            padding = 0,
            bordersize = focus_visible and focus_zone == "content" and focused_content_index == extended_focus_index
                and math.max(Size.border.default, scale(3)) or 0,
            background = Blitbuffer.COLOR_WHITE,
            extended_check,
        })
        table.insert(group, TextBoxWidget:new{
            text = _("Keep downloaded books available after the scheduled loan expiration."),
            width = content_inner_w,
            height = scale(28),
            height_adjust = true,
            alignment = "left",
            face = Font:getFace("smallinfofont", 10),
            height_overflow_show_ellipsis = true,
        })
        table.insert(group, VerticalSpan:new{ width = scale(3) })
        table.insert(group, sectionHeading(_("Book Storage")))
        table.insert(group, VerticalSpan:new{ width = scale(1) })

        local current = plugin.controller.settings.book_path_template or PathTemplate.DEFAULT_TEMPLATE
        table.insert(group, TextBoxWidget:new{
            text = _("Current:") .. " " .. current .. "\n" .. _("Example:") .. " " .. plugin:storagePreview(current),
            width = content_inner_w,
            height = scale(52),
            height_adjust = true,
            alignment = "left",
            face = Font:getFace("smallinfofont", 11),
            height_overflow_show_ellipsis = true,
        })
        table.insert(group, VerticalSpan:new{ width = scale(3) })

        local preset_gap = scale(6)
        local preset_w = math.max(1, math.floor((content_inner_w - preset_gap) / 2))
        local function presetButton(text, template)
            return tapFrame(text, preset_w, scale(28), {
                font_size = 12,
                bold = true,
                bordersize = border,
                background = Blitbuffer.COLOR_WHITE,
                radius = scale(2),
            }, function()
                plugin:applyBookPathTemplate(template, function()
                    reopen("downloads", values, false)
                end)
            end)
        end
        table.insert(group, HorizontalGroup:new{
            align = "center",
            presetButton(_("Author / Title"), "{home}/{author:first}/{title}.{ext}"),
            HorizontalSpan:new{ width = preset_gap },
            presetButton(_("Author / Series / Title"), PathTemplate.DEFAULT_TEMPLATE),
        })
        table.insert(group, VerticalSpan:new{ width = scale(4) })
        table.insert(group, HorizontalGroup:new{
            align = "center",
            presetButton(_("Library / Author / Title"), "{home}/{library}/{author:first}/{title}.{ext}"),
            HorizontalSpan:new{ width = preset_gap },
            presetButton(_("All books in Home"), "{home}/{title}.{ext}"),
        })
        table.insert(group, VerticalSpan:new{ width = scale(4) })
        table.insert(group, tapFrame(_("Custom template…"), content_inner_w, scale(30), {
            font_size = 13,
            bold = true,
            bordersize = border,
            background = Blitbuffer.COLOR_WHITE,
            radius = scale(2),
        }, function()
            plugin:showCustomBookStorage(function()
                reopen("downloads", values, false)
            end)
        end))

        return TopContainer:new{
            dimen = Geom:new{ w = content_w, h = body_h },
            FrameContainer:new{
                width = content_w,
                height = body_h,
                margin = 0,
                padding = 0,
                padding_top = scale(4),
                padding_bottom = scale(4),
                padding_left = page_pad,
                padding_right = page_pad,
                bordersize = 0,
                background = Blitbuffer.COLOR_WHITE,
                group,
            },
        }
    end

    local function developerPage()
        local group = VerticalGroup:new{ align = "left" }
        table.insert(group, pageHeading(_("Developer"), _("Developer Mode is enabled.")))
        table.insert(group, VerticalSpan:new{ width = scale(3) })
        table.insert(group, sectionHeading(_("Book Storage")))
        table.insert(group, VerticalSpan:new{ width = scale(1) })

        local current = plugin.controller.settings.book_path_template or PathTemplate.DEFAULT_TEMPLATE
        table.insert(group, TextBoxWidget:new{
            text = _("Current:") .. " " .. current .. "\n" .. _("Example:") .. " " .. plugin:storagePreview(current),
            width = content_inner_w,
            height = scale(52),
            height_adjust = true,
            alignment = "left",
            face = Font:getFace("smallinfofont", 11),
            height_overflow_show_ellipsis = true,
        })
        table.insert(group, VerticalSpan:new{ width = scale(3) })

        local preset_gap = scale(6)
        local preset_w = math.max(1, math.floor((content_inner_w - preset_gap) / 2))
        local function presetButton(text, template)
            return tapFrame(text, preset_w, scale(28), {
                font_size = 12,
                bold = true,
                bordersize = border,
                background = Blitbuffer.COLOR_WHITE,
                radius = scale(2),
            }, function()
                plugin:applyBookPathTemplate(template, function()
                    reopen("developer", values, false)
                end)
            end)
        end
        table.insert(group, HorizontalGroup:new{
            align = "center",
            presetButton(_("Author / Title"), "{home}/{author:first}/{title}.{ext}"),
            HorizontalSpan:new{ width = preset_gap },
            presetButton(_("Author / Series / Title"), PathTemplate.DEFAULT_TEMPLATE),
        })
        table.insert(group, VerticalSpan:new{ width = scale(4) })
        table.insert(group, HorizontalGroup:new{
            align = "center",
            presetButton(_("Library / Author / Title"), "{home}/{library}/{author:first}/{title}.{ext}"),
            HorizontalSpan:new{ width = preset_gap },
            presetButton(_("All books in Home"), "{home}/{title}.{ext}"),
        })
        table.insert(group, VerticalSpan:new{ width = scale(4) })
        table.insert(group, tapFrame(_("Custom template…"), content_inner_w, scale(30), {
            font_size = 13,
            bold = true,
            bordersize = border,
            background = Blitbuffer.COLOR_WHITE,
            radius = scale(2),
        }, function()
            plugin:showCustomBookStorage(function()
                reopen("developer", values, false)
            end)
        end))

        table.insert(group, VerticalSpan:new{ width = scale(7) })
        table.insert(group, sectionHeading(_("Developer Mode")))
        table.insert(group, VerticalSpan:new{ width = scale(1) })
        table.insert(group, tapFrame(_("Developer Mode / Diagnostics"), content_inner_w, scale(30), {
            font_size = 13,
            bold = true,
            bordersize = border,
            background = Blitbuffer.COLOR_WHITE,
            radius = scale(2),
        }, function()
            plugin:showCleanupDiagnosticPrompt(function(enabled)
                reopen(enabled and "developer" or "general", values, false)
            end)
        end))

        return TopContainer:new{
            dimen = Geom:new{ w = content_w, h = body_h },
            FrameContainer:new{
                width = content_w,
                height = body_h,
                margin = 0,
                padding = 0,
                padding_top = scale(4),
                padding_bottom = scale(4),
                padding_left = page_pad,
                padding_right = page_pad,
                bordersize = 0,
                background = Blitbuffer.COLOR_WHITE,
                group,
            },
        }
    end

    local developer_enabled = plugin.controller.settings.developer_mode == true
    local page
    if section == "library" then
        page = shelfPage()
    elseif section == "accounts" then
        page = simplePage(_("Accounts"), _("Manage Libby and Adobe/ByteBooks authentication."), {
            { text = _("Libby Account"), callback = function()
                plugin:showLibbySettings()
            end },
            { text = _("ByteBooks / Adobe Authorization"), callback = function()
                plugin:showAdobeSettings()
            end },
            { text = _("Account Backup & Restore"), callback = function()
                plugin:showAccountBackupSettings()
            end },
        })
    elseif section == "downloads" then
        page = downloadsPage()
    elseif section == "developer" and developer_enabled then
        page = developerPage()
    elseif section == "about" then
        page = simplePage(_("About"), _("Libby Dashboard") .. " v" .. plugin.PLUGIN_VERSION, {
            { text = _("Credits"), callback = function()
                plugin:showCredits(function(enabled)
                    reopen(enabled and "developer" or "about", values, false)
                end)
            end },
        })
    elseif section == "general" then
        page = simplePage(_("General"), _("Libby Dashboard") .. " v" .. plugin.PLUGIN_VERSION, {
            { text = _("Check for Updates"), callback = function()
                require("libby_dashboard_updater").check(plugin, true)
            end },
        })
    else
        page = simplePage(_("General"), _("Libby Dashboard") .. " v" .. plugin.PLUGIN_VERSION)
        section = "general"
    end

    local nav_items = {
        { id = "general", text = _("General") },
        { id = "accounts", text = _("Accounts") },
        { id = "downloads", text = _("Downloads") },
        { id = "library", text = _("Library / Shelves") },
    }
    if developer_enabled then
        table.insert(nav_items, { id = "developer", text = _("Developer") })
    end
    table.insert(nav_items, { id = "about", text = _("About") })

    if focus_state.nav_index == nil then
        for index, item in ipairs(nav_items) do
            if item.id == section then
                focused_nav_index = index
                break
            end
        end
    end
    focused_nav_index = math.max(1, math.min(#nav_items, focused_nav_index))
    if #content_actions == 0 then
        focused_content_index = 1
        if focus_zone == "content" then focus_zone = "nav" end
    else
        focused_content_index = math.max(1, math.min(#content_actions, focused_content_index))
    end

    local nav_row_h = scale(34)
    local nav_gap = 0
    if #nav_items > 1 then
        nav_gap = math.floor((body_h - nav_row_h * #nav_items - scale(8)) / (#nav_items - 1))
        nav_gap = math.max(0, math.min(scale(22), nav_gap))
    end
    local nav_used_h = nav_row_h * #nav_items + nav_gap * math.max(0, #nav_items - 1)
    local nav_top_pad = math.max(scale(4), math.floor((body_h - nav_used_h) / 2))

    local nav = VerticalGroup:new{ align = "left" }
    table.insert(nav, VerticalSpan:new{ width = nav_top_pad })
    for index, item in ipairs(nav_items) do
        local selected = item.id == section
        local nav_index = index
        local callback = function()
            focused_nav_index = nav_index
            if item.id ~= section then reopen(item.id, values, false) end
        end
        nav_actions[index] = callback
        table.insert(nav, tapFrame(item.text, nav_w, nav_row_h, {
            align = "left",
            pad = scale(5),
            font_size = 15,
            bold = true,
            background = selected and Blitbuffer.COLOR_LIGHT_GRAY or Blitbuffer.COLOR_WHITE,
            navigation = false,
            focused = focus_visible and focus_zone == "nav" and focused_nav_index == index,
        }, callback))
        if index < #nav_items and nav_gap > 0 then
            table.insert(nav, VerticalSpan:new{ width = nav_gap })
        end
    end

    local nav_frame = TopContainer:new{
        dimen = Geom:new{ w = nav_w, h = body_h },
        nav,
    }

    local close_w = header_h
    local header_content_h = math.max(1, header_h - divider_w)
    local title_w = math.max(1, dialog_inner_w - 2 * close_w)
    local header_row = HorizontalGroup:new{
        align = "center",
        HorizontalSpan:new{ width = close_w },
        CenterContainer:new{
            dimen = Geom:new{ w = title_w, h = header_content_h },
            TextWidget:new{
                text = _("Settings"),
                face = Font:getFace("cfont", 15),
                bold = true,
                max_width = title_w,
            },
        },
        tapFrame("X", close_w, header_content_h, {
            font_size = 16,
            bold = false,
            navigation = false,
            focused = focus_visible and focus_zone == "close",
        }, closeAndRevert),
    }
    local header = VerticalGroup:new{
        TopContainer:new{
            dimen = Geom:new{ w = dialog_inner_w, h = header_content_h },
            header_row,
        },
        LineWidget:new{
            dimen = Geom:new{ w = dialog_inner_w, h = divider_w },
        },
    }

    local shell = FrameContainer:new{
        width = dialog_w,
        height = dialog_h,
        margin = 0,
        padding = 0,
        bordersize = shell_border,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "center",
            header,
            HorizontalGroup:new{
                align = "center",
                nav_frame,
                LineWidget:new{
                    dimen = Geom:new{ w = divider_w, h = body_h },
                },
                page,
            },
        },
    }

    dialog = InputContainer:new{
        dimen = Geom:new{ w = screen.w, h = screen.h },
        CenterContainer:new{
            dimen = Geom:new{ w = screen.w, h = screen.h },
            shell,
        },
    }
    dialog.key_events = Dpad.dialog_key_events(Device)

    local function revealFocus()
        if focus_visible then return false end
        focus_visible = true
        focus_zone = "nav"
        redrawFocus()
        return true
    end

    dialog.onDpadBack = function()
        closeAndRevert()
        return true
    end
    dialog.onDpadUp = function()
        if revealFocus() then return true end
        if focus_zone == "nav" then
            focused_nav_index = ((focused_nav_index - 2) % #nav_items) + 1
        elseif focus_zone == "content" and #content_actions > 0 then
            focused_content_index = ((focused_content_index - 2) % #content_actions) + 1
        elseif focus_zone == "close" then
            focus_zone = "nav"
        end
        redrawFocus()
        return true
    end
    dialog.onDpadDown = function()
        if revealFocus() then return true end
        if focus_zone == "nav" then
            focused_nav_index = (focused_nav_index % #nav_items) + 1
        elseif focus_zone == "content" and #content_actions > 0 then
            focused_content_index = (focused_content_index % #content_actions) + 1
        elseif focus_zone == "close" then
            focus_zone = "nav"
        end
        redrawFocus()
        return true
    end
    dialog.onDpadLeft = function()
        if revealFocus() then return true end
        if focus_zone == "content" or focus_zone == "close" then
            focus_zone = "nav"
        end
        redrawFocus()
        return true
    end
    dialog.onDpadRight = function()
        if revealFocus() then return true end
        if focus_zone == "nav" then
            focus_zone = #content_actions > 0 and "content" or "close"
        elseif focus_zone == "content" then
            focus_zone = "close"
        end
        redrawFocus()
        return true
    end
    dialog.onDpadPress = function()
        if revealFocus() then return true end
        if focus_zone == "close" then
            closeAndRevert()
        elseif focus_zone == "nav" then
            local action = nav_actions[focused_nav_index]
            if action then action() end
        elseif focus_zone == "content" then
            local action = content_actions[focused_content_index]
            if action then action() end
        end
        return true
    end

    plugin.settings_dialog = dialog
    UIManager:show(dialog)
end

return SettingsDialog
