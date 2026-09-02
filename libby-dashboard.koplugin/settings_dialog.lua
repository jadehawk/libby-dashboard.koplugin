local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
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
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local TopContainer = require("ui/widget/container/topcontainer")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")

local SettingsDialog = {}

local function copyState(state)
    return {
        main_columns = state.main_columns,
        main_rows = state.main_rows,
        grid_columns = state.grid_columns,
        grid_rows = state.grid_rows,
        list_rows = state.list_rows,
    }
end

local function currentState(plugin)
    local settings = plugin.controller.settings
    return {
        main_columns = math.max(2, math.min(8, tonumber(settings.libby_shelf_columns) or 4)),
        main_rows = math.max(1, math.min(5, tonumber(settings.libby_shelf_rows) or 2)),
        grid_columns = math.max(2, math.min(8, tonumber(settings.libby_expanded_grid_columns) or 4)),
        grid_rows = math.max(1, math.min(6, tonumber(settings.libby_expanded_grid_rows) or 3)),
        list_rows = math.max(4, math.min(12, tonumber(settings.libby_expanded_list_rows) or 7)),
    }
end

local function preview(plugin, state)
    local settings = plugin.controller.settings
    if plugin.catalog_browser and UIManager:isWidgetShown(plugin.catalog_browser) then
        plugin.catalog_browser:setShelfLayout(state.main_columns, state.main_rows)
        plugin.catalog_browser:setExpandedLayout(state.grid_columns, state.grid_rows, state.list_rows)
    else
        settings.libby_shelf_columns = state.main_columns
        settings.libby_shelf_rows = state.main_rows
        settings.libby_expanded_grid_columns = state.grid_columns
        settings.libby_expanded_grid_rows = state.grid_rows
        settings.libby_expanded_list_rows = state.list_rows
    end
end

function SettingsDialog.show(plugin, section, original, values)
    section = section or "general"
    original = original or currentState(plugin)
    values = values or copyState(original)

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
        local pad = opts.pad or scale(6)
        local bordersize = opts.bordersize or 0
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

    local function reopen(next_section, next_values, apply_preview)
        closeDialog()
        if apply_preview and next_values then preview(plugin, next_values) end
        SettingsDialog.show(plugin, next_section or section, original, next_values or values)
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

    local function actionButton(text, width, callback, primary)
        return tapFrame(text, width, scale(33), {
            font_size = 14,
            bold = true,
            bordersize = border,
            background = primary and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
            fgcolor = primary and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK,
            radius = scale(2),
        }, callback)
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

        table.insert(top, sectionHeading(_("Main UI (Libraries Shelf)")))
        table.insert(top, VerticalSpan:new{ width = scale(2) })
        table.insert(top, HorizontalGroup:new{
            align = "center",
            settingField(_("Columns (Grid):"), "main_columns", 2, 8, first_label_w, selector_w),
            HorizontalSpan:new{ width = field_gap },
            settingField(_("Rows:"), "main_rows", 1, 5, second_label_w, selector_w),
        })
        table.insert(top, VerticalSpan:new{ width = scale(6) })

        table.insert(top, sectionHeading(_("Expanded View - Grid (Book Cards)")))
        table.insert(top, VerticalSpan:new{ width = scale(2) })
        table.insert(top, HorizontalGroup:new{
            align = "center",
            settingField(_("Columns:"), "grid_columns", 2, 8, first_label_w, selector_w),
            HorizontalSpan:new{ width = field_gap },
            settingField(_("Rows:"), "grid_rows", 1, 6, second_label_w, selector_w),
        })
        table.insert(top, VerticalSpan:new{ width = scale(6) })

        table.insert(top, sectionHeading(_("Expanded View - List (Book List)")))
        table.insert(top, VerticalSpan:new{ width = scale(2) })
        table.insert(top, settingField(_("Rows per page:"), "list_rows", 4, 12, first_label_w, selector_w))
        table.insert(top, VerticalSpan:new{ width = scale(6) })

        local footer_gap = math.max(scale(12), math.floor(content_inner_w * 0.035))
        local reset_w = math.max(scale(140), math.floor(content_inner_w * 0.40))
        local save_w = math.max(scale(82), math.floor(content_inner_w * 0.22))
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
                        main_columns = 4,
                        main_rows = 2,
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
                end, true),
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
        local download_buttons = {}
        if plugin.controller.settings.cleanup_mode == "dry_run" then
            table.insert(download_buttons, {
                text = _("Book Storage"),
                callback = function()
                    plugin:showBookStorageSettings()
                end,
            })
        end
        page = simplePage(_("Downloads"), _("Configure download and storage behavior."), download_buttons)
    elseif section == "about" then
        page = simplePage(_("About"), _("Libby Dashboard") .. " v" .. plugin.PLUGIN_VERSION, {
            { text = _("Credits"), callback = function()
                plugin:showCredits()
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
        { id = "about", text = _("About") },
    }

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
        table.insert(nav, tapFrame(item.text, nav_w, nav_row_h, {
            align = "left",
            pad = scale(5),
            font_size = 15,
            bold = true,
            background = selected and Blitbuffer.COLOR_LIGHT_GRAY or Blitbuffer.COLOR_WHITE,
        }, function()
            if item.id ~= section then reopen(item.id, values, false) end
        end))
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
    plugin.settings_dialog = dialog
    UIManager:show(dialog)
end

return SettingsDialog
