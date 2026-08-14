local source = debug.getinfo(1, "S").source or ""
local source_path = source:gsub("^@", "")
local plugin_root = source_path:match("^(.*)[/\\]main%.lua$")
if plugin_root then
    package.path = plugin_root .. "/dependencies/?.lua;" .. plugin_root .. "/dependencies/?/?.lua;" .. package.path
end

local Device = require("device")
local DataStorage = require("datastorage")
local DocumentRegistry = require("document/documentregistry")
local DocSettings = require("docsettings")
local LuaSettings = require("luasettings")
local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local NetworkMgr = require("ui/network/manager")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local rapidjson = require("rapidjson")
local util = require("ffi/util")
local koUtil = require("util")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local KOReaderController = require("koreader_controller")
local KOReaderTransport = require("koreader_transport")
local LibbyCatalog = require("libby_catalog")
local LoanModel = require("loan_model")
local PathTemplate = require("path_template")

-- Load the vendored Adobe stack while PluginLoader still has this plugin's
-- temporary package.path active. KOReader restores package.path after main.lua
-- returns, so lazy-loading these modules later would lose dependencies/?.lua.
require("adobe.adobe")
require("adobe.fulfillment")

local Libby = WidgetContainer:extend{
    name = "libby",
    fullname = _("Libby"),
}

local function safeDisplayText(value, max_bytes)
    local text = tostring(value or "")
    text = text:gsub("[%z\1-\31\127]", " "):gsub("%s+", " ")
    text = util.fixUtf8(text, "?")
    max_bytes = max_bytes or 96
    if #text > max_bytes then
        text = util.fixUtf8(text:sub(1, math.max(1, max_bytes - 3)), "?") .. "..."
    end
    return text
end

function Libby:init()
    self.settings_file = DataStorage:getSettingsDir() .. "/libby.lua"
    self.settings_store = LuaSettings:open(self.settings_file)
    self.controller = KOReaderController.new{
        reader_settings = G_reader_settings,
        settings_store = self.settings_store,
        device = Device,
    }
    self.controller:load()
    self:registerAcsmProvider()
    self.ui.menu:registerToMainMenu(self)
end

function Libby:registerAcsmProvider()
    local provider = {
        provider_name = self.fullname,
        provider = self.name,
        order = 36,
        disable_file = true,
        disable_type = false,
        -- addProvider() already exposes this provider through KOReader's normal
        -- document-provider selection. Avoid a duplicate auxiliary entry.
        enabled_func = function() return false end,
    }

    local registered = false
    for i = #DocumentRegistry.providers, 1, -1 do
        local entry = DocumentRegistry.providers[i]
        if entry.extension == "acsm" and entry.provider and entry.provider.provider == self.name then
            if registered then
                table.remove(DocumentRegistry.providers, i)
            else
                entry.mimetype = "application/vnd.adobe.adept+xml"
                entry.provider = provider
                entry.weight = 90
                registered = true
            end
        end
    end

    if not registered then
        -- Weight below acsm.koplugin's 100 keeps that plugin's existing default
        -- when both are installed, while still making Libby selectable for ACSM.
        DocumentRegistry:addProvider("acsm", "application/vnd.adobe.adept+xml", provider, 90)
    else
        DocumentRegistry.known_providers[self.name] = provider
    end
end

function Libby:isFileTypeSupported(file)
    return type(file) == "string" and koUtil.getFileNameSuffix(file):lower() == "acsm"
end

function Libby:externalAcsmOutputPath(file)
    local input = io.open(file, "rb")
    local contents = input and input:read("*a") or ""
    if input then input:close() end
    local extension = contents:find("application/pdf", 1, true) and ".pdf" or ".epub"
    local base = file:gsub("%.[Aa][Cc][Ss][Mm]$", "")
    local desired = base .. extension
    if not koUtil.pathExists(desired) then return desired end
    for index = 1, 999 do
        local candidate = base .. " (" .. tostring(index) .. ")" .. extension
        if not koUtil.pathExists(candidate) then return candidate end
    end
    return desired
end

function Libby:openFile(file)
    if not self:isFileTypeSupported(file) then return end

    if NetworkMgr:willRerunWhenOnline(function() self:openFile(file) end) then return end

    Trapper:wrap(function()
        Trapper:info(_("Preparing ACSM..."), false, true)
        local registration, registration_err = self.controller:ensure_adobe_registration()
        if not registration then
            Trapper:reset()
            UIManager:show(InfoMessage:new{
                text = _("Adobe authorization failed:") .. "\n\n" .. tostring(registration_err),
            })
            return
        end

        local output = self:externalAcsmOutputPath(file)
        Trapper:info(_("Downloading book..."), false, true)
        local result, fulfill_err = self.controller:fulfill_acsm(file, output)
        if not result then
            Trapper:reset()
            UIManager:show(InfoMessage:new{
                text = _("ACSM processing failed:") .. "\n\n" .. tostring(fulfill_err),
            })
            return
        end

        if self.ui.file_chooser then self.ui.file_chooser:refreshPath() end
        Trapper:clear()
        if self.ui and type(self.ui.openFile) == "function" then
            UIManager:nextTick(function() self.ui:openFile(result.outputPath or output) end)
        else
            UIManager:show(InfoMessage:new{
                text = _("Book downloaded successfully:") .. "\n\n" .. tostring(result.outputPath or output),
            })
        end
    end)
end

function Libby:showStatus()
    local status = self.controller:status()
    local adobe = self.controller:adobe_summary()
    local adobe_status = _("not registered")
    if adobe.registered then
        adobe_status = adobe.authorizationType == "account" and _("ByteBooks account") or _("anonymous")
        if adobe.authorizationType == "account" and adobe.username then
            adobe_status = adobe_status .. " (" .. tostring(adobe.username) .. ")"
        end
    end
    local lines = {
        _("Libby: ") .. (status.libby_authenticated and _("authenticated") or _("not authenticated")),
        _("Adobe: ") .. adobe_status,
        _("Home: ") .. tostring(status.home_dir),
        _("Book template: ") .. tostring(status.book_path_template),
    }
    UIManager:show(InfoMessage:new{ text = table.concat(lines, "\n") })
end

function Libby:showPending(feature)
    UIManager:show(InfoMessage:new{
        text = feature .. "\n\n" .. _("The KOReader network/UI adapter is still being connected to the tested Libby core."),
    })
end

function Libby:showLibraryCards()
    NetworkMgr:runWhenOnline(function()
        local state, err = self.controller:sync_libby()
        if not state then
            UIManager:show(InfoMessage:new{ text = _("Could not load library cards:") .. "\n\n" .. tostring(err) })
            return
        end
        local cards = state.cards or {}
        if #cards == 0 then
            UIManager:show(InfoMessage:new{ text = _("No library cards found.") })
            return
        end
        local lines = { _("Library cards") }
        for index, card in ipairs(cards) do
            table.insert(lines, string.format("%d. %s", index, LoanModel.card_name(card)))
        end
        UIManager:show(InfoMessage:new{ text = table.concat(lines, "\n\n") })
    end)
end

function Libby:removeTrackedBook(path)
    if type(path) ~= "string" or path == "" then return end
    pcall(DocSettings.updateLocation, DocSettings, path, nil)
    os.remove(path)
end

function Libby:downloadLoan(loan)
    if not loan or not loan.adobe_format then
        local kind = loan and loan.media_type
        local message = kind == "audiobook" and _("Audiobooks are not currently supported by the Libby plugin.")
            or kind == "magazine" and _("Magazines are not currently supported by the Libby plugin.")
            or _("This loan has no supported Adobe EPUB/PDF format.")
        UIManager:show(InfoMessage:new{ text = message })
        return
    end

    local wifi_on = type(NetworkMgr.isWifiOn) ~= "function" or NetworkMgr:isWifiOn()
    local connected = type(NetworkMgr.isConnected) ~= "function" or NetworkMgr:isConnected()
    if not (wifi_on and connected) then
        UIManager:show(InfoMessage:new{ text = _("Wi-Fi is not available. Connect to Wi-Fi and try again.") })
        return
    end

    Trapper:wrap(function()
        Trapper:info(_("Fetching book from Libby…\n\nPlease stand by."), false, true)
        local acsm, err = self.controller:download_loan_acsm(loan)
        if not acsm then
            Trapper:reset()
            UIManager:show(InfoMessage:new{ text = _("Could not download ACSM:") .. "\n\n" .. tostring(err) })
            return
        end
        local destination = self.controller:book_destination(loan, "acsm")
        local parent = util.dirname(destination)
        if parent and parent ~= "" and not koUtil.makePath(parent) then
            Trapper:reset()
            UIManager:show(InfoMessage:new{ text = _("Could not create destination folder:") .. "\n\n" .. tostring(parent) })
            return
        end
        local file, file_err = io.open(destination, "wb")
        if not file then
            Trapper:reset()
            UIManager:show(InfoMessage:new{ text = _("Could not save ACSM:") .. "\n\n" .. tostring(file_err) })
            return
        end
        file:write(acsm)
        file:close()

        if not self.controller:adobe_registered() then
            Trapper:info(_("Preparing Adobe authorization..."), false, true)
            local registered, register_err = self.controller:ensure_adobe_registration()
            if not registered then
                Trapper:reset()
                UIManager:show(InfoMessage:new{
                    text = _("ACSM downloaded successfully:") .. "\n\n" .. destination
                        .. "\n\n" .. _("Could not prepare Adobe authorization:") .. "\n" .. tostring(register_err),
                })
                return
            end
        end

        Trapper:info(_("Downloading and preparing book…"), false, true)
        local extension = loan.adobe_format:find("pdf", 1, true) and "pdf" or "epub"
        local output = self.controller:book_destination(loan, extension)
        local fulfilled, fulfill_err = self.controller:fulfill_acsm(destination, output)
        if not fulfilled then
            Trapper:reset()
            UIManager:show(InfoMessage:new{ text = _("ACSM saved, but Adobe fulfillment failed:") .. "\n\n" .. tostring(fulfill_err) })
            return
        end
        os.remove(destination)
        local downloaded_path = fulfilled.outputPath or output
        self.controller:track_downloaded_loan(loan, downloaded_path)
        Trapper:clear()
        UIManager:show(InfoMessage:new{ text = _("Book downloaded successfully:") .. "\n\n" .. tostring(downloaded_path) })
    end)
end

function Libby:showLoanDetails(loan)
    local lines = { loan.title or _("Untitled") }
    if loan.author then table.insert(lines, _("Author: ") .. tostring(loan.author)) end
    if loan.library then table.insert(lines, _("Library: ") .. tostring(loan.library)) end
    if loan.series then
        local series_text = tostring(loan.series)
        if loan.series_index ~= nil then series_text = series_text .. " #" .. tostring(loan.series_index) end
        table.insert(lines, _("Series: ") .. series_text)
    end
    if loan.days_remaining ~= nil then
        local suffix = loan.days_remaining == 1 and _(" day remaining") or _(" days remaining")
        table.insert(lines, _("Loan: ") .. tostring(loan.days_remaining) .. suffix)
    end
    table.insert(lines, _("Format: ") .. tostring(loan.adobe_format or loan.media_type or _("Unsupported")))
    local dialog
    local buttons = {}
    if loan.adobe_format then
        table.insert(buttons, { { text = _("Download"), callback = function()
            UIManager:close(dialog)
            self:downloadLoan(loan)
        end } })
    end
    table.insert(buttons, { { text = _("Close"), callback = function() UIManager:close(dialog) end } })
    dialog = ButtonDialog:new{ title = table.concat(lines, "\n"), buttons = buttons }
    UIManager:show(dialog)
end

function Libby:showLoans()
    NetworkMgr:runWhenOnline(function()
        local state, err = self.controller:sync_libby()
        if not state then
            UIManager:show(InfoMessage:new{ text = _("Could not load loans:") .. "\n\n" .. tostring(err) })
            return
        end

        local loans = LoanModel.list(state.loans or {}, state.cards or {})
        UIManager:show(InfoMessage:new{
            text = string.format(_("Found %d loans."), #loans),
        })
    end)
end

function Libby:testConnection()
    NetworkMgr:runWhenOnline(function()
        local ok, err = self.controller:test_libby_connection()
        UIManager:show(InfoMessage:new{
            text = ok and _("Libby connection successful. KOReader reached the Libby service and received a valid chip response.")
                or (_("Libby connection failed:") .. "\n\n" .. tostring(err)),
        })
    end)
end

function Libby:showLibbySetup()
    UIManager:show(ConfirmBox:new{
        text = _("On an already signed-in Libby device, open:\n\nMenu → Copy To Another Device → Enter Setup Code\n\nThe setup code is valid for only 60 seconds. Have that screen ready before generating the code."),
        cancel_text = _("Cancel"),
        ok_text = _("Generate code"),
        ok_callback = function() self:generateLibbySetupCode() end,
    })
end

function Libby:generateLibbySetupCode()
    NetworkMgr:runWhenOnline(function()
        local setup, err = self.controller:begin_libby_setup()
        if not setup then
            UIManager:show(InfoMessage:new{ text = _("Could not generate Libby setup code:") .. "\n\n" .. tostring(err) })
            return
        end
        self:showLibbySetupCountdown()
    end)
end

function Libby:showLibbySetupCountdown()
    local pending = self.controller:pending_libby_setup()
    if not pending or pending.remaining <= 0 then
        self.controller:clear_pending_libby_setup()
        self.controller:save()
        self:offerLibbySetupRegeneration()
        return
    end

    local dialog
    local tick
    local function text_for(remaining)
        return _("Enter this code on the signed-in Libby device:") .. "\n\n    " .. tostring(pending.code)
            .. "\n\n" .. string.format(_("Code expires in: %d seconds"), remaining)
            .. "\n\n" .. _("When Libby shows Done/OK, tap Verify now.")
    end

    local function stop_tick()
        if tick then UIManager:unschedule(tick) end
    end

    dialog = ConfirmBox:new{
        text = text_for(pending.remaining),
        cancel_text = _("Cancel"),
        ok_text = _("Verify now"),
        dismissable = false,
        cancel_callback = function()
            stop_tick()
            self.controller:clear_pending_libby_setup()
            self.controller:save()
        end,
        ok_callback = function()
            stop_tick()
            self:verifyLibbySetupCode()
        end,
    }

    tick = function()
        local current = self.controller:pending_libby_setup()
        if not current or current.remaining <= 0 then
            stop_tick()
            if dialog then UIManager:close(dialog) end
            self.controller:clear_pending_libby_setup()
            self.controller:save()
            self:offerLibbySetupRegeneration()
            return
        end
        if dialog and dialog.text_group and dialog.text_group[1] and dialog.text_group[1].setText then
            dialog.text_group[1]:setText(text_for(current.remaining))
            UIManager:setDirty(dialog, "ui")
        end
        UIManager:scheduleIn(1, tick)
    end

    UIManager:show(dialog)
    UIManager:scheduleIn(1, tick)
end

function Libby:verifyLibbySetupCode()
    NetworkMgr:runWhenOnline(function()
        local state, err = self.controller:complete_libby_setup()
        if not state then
            local pending = self.controller:pending_libby_setup()
            if pending and pending.remaining > 0 then
                UIManager:show(ConfirmBox:new{
                    text = _("Libby has not accepted this code yet.") .. "\n\n" .. tostring(err),
                    cancel_text = _("Cancel setup"),
                    ok_text = _("Try again"),
                    cancel_callback = function()
                        self.controller:clear_pending_libby_setup()
                        self.controller:save()
                    end,
                    ok_callback = function() self:showLibbySetupCountdown() end,
                })
            else
                self.controller:clear_pending_libby_setup()
                self.controller:save()
                self:offerLibbySetupRegeneration()
            end
            return
        end

        UIManager:show(InfoMessage:new{
            text = _("Libby authentication complete.") .. "\n\n"
                .. _("Library cards found: ") .. tostring(#(state.cards or {})) .. "\n"
                .. _("Current loans found: ") .. tostring(#(state.loans or {})),
        })
    end)
end

function Libby:offerLibbySetupRegeneration()
    UIManager:show(ConfirmBox:new{
        text = _("The 60-second Libby setup code has expired."),
        cancel_text = _("Cancel"),
        ok_text = _("Generate another"),
        ok_callback = function() self:generateLibbySetupCode() end,
    })
end

function Libby:coverCacheDir()
    return DataStorage:getDataDir() .. "/cache/libby-covers"
end

function Libby:coverCachePath(loan)
    if type(loan) ~= "table" or not loan.cover_url then return nil end
    local key = tostring(loan.id or loan.title or loan.cover_url):gsub("[^%w%-_]", "_")
    local path = self:coverCacheDir() .. "/" .. key .. ".jpg"
    local file = io.open(path, "rb")
    if file then
        file:close()
        return path
    end
    return nil
end

function Libby:prefetchBrowserCovers(browser)
    local snapshot = browser and browser.snapshot or nil
    if type(snapshot) ~= "table" or type(snapshot.loans) ~= "table" then return end
    local missing = {}
    for _, loan in ipairs(snapshot.loans) do
        if loan.cover_url and not self:coverCachePath(loan) then table.insert(missing, loan) end
    end
    if #missing == 0 then return end

    NetworkMgr:runWhenConnected(function()
        Trapper:wrap(function()
            local completed = Trapper:dismissableRunInSubprocess(function()
                local dir = self:coverCacheDir()
                if not koUtil.makePath(dir) then return false end
                local transport = KOReaderTransport.new()
                for _, loan in ipairs(missing) do
                    local response = transport:request({
                        base_url = loan.cover_url,
                        path = "",
                        method = "GET",
                        headers = { ["Accept"] = "image/*" },
                    })
                    if response and response.status == 200 and type(response.raw_body) == "string" and #response.raw_body > 0 then
                        local key = tostring(loan.id or loan.title or loan.cover_url):gsub("[^%w%-_]", "_")
                        local path = dir .. "/" .. key .. ".jpg"
                        local file = io.open(path .. ".part", "wb")
                        if file then
                            file:write(response.raw_body)
                            file:close()
                            os.remove(path)
                            os.rename(path .. ".part", path)
                        end
                    end
                end
                return true
            end, nil, true)
            if completed then
                UIManager:nextTick(function()
                    if browser and UIManager:isWidgetShown(browser) then browser:updateItems() end
                end)
            end
        end)
    end)
end

function Libby:storagePreview(template)
    local model = {
        title = "The Way of Kings",
        author = "Brandon Sanderson",
        authors = { { name = "Brandon Sanderson", firstName = "Brandon", lastName = "Sanderson" } },
        series = "The Stormlight Archive",
        series_index = 1,
        library = "Example Library",
    }
    return PathTemplate.resolve(template, model, {
        home = G_reader_settings:readSetting("home_dir") or "/Books",
        ext = "epub",
    })
end

function Libby:applyBookPathTemplate(template)
    local ok, err = self.controller:set_book_path_template(template)
    if not ok then
        UIManager:show(InfoMessage:new{ text = _("Invalid destination template:") .. "\n\n" .. tostring(err) })
        return
    end
    UIManager:show(InfoMessage:new{
        text = _("Book destination updated.") .. "\n\n" .. tostring(template)
            .. "\n\n" .. _("Example:") .. "\n" .. self:storagePreview(template),
    })
end

function Libby:showCustomBookStorage()
    local current = self.controller.settings.book_path_template or PathTemplate.DEFAULT_TEMPLATE
    local dialog
    dialog = MultiInputDialog:new{
        title = _("Custom Book Destination"),
        description = _("Build the destination with tokens. Available tokens:") .. "\n"
            .. table.concat(PathTemplate.tokens(), "  ")
            .. "\n\n" .. _("Current example:") .. "\n" .. self:storagePreview(current),
        fields = { { text = current, hint = PathTemplate.DEFAULT_TEMPLATE } },
        buttons = {
            {
                { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
                { text = _("Save"), is_enter_default = true, callback = function()
                    local fields = dialog:getFields()
                    local value = koUtil.trim((fields and fields[1]) or "")
                    local valid, err = PathTemplate.validate(value)
                    if not valid then
                        UIManager:show(InfoMessage:new{ text = _("Invalid destination template:") .. "\n\n" .. tostring(err) })
                        return
                    end
                    UIManager:close(dialog)
                    self:applyBookPathTemplate(value)
                end },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Libby:showBookStorageSettings()
    local current = self.controller.settings.book_path_template or PathTemplate.DEFAULT_TEMPLATE
    local dialog
    local function preset(label, template)
        return { { text = label, callback = function()
            UIManager:close(dialog)
            self:applyBookPathTemplate(template)
        end } }
    end
    dialog = ButtonDialog:new{
        title = _("Book Storage") .. "\n" .. current .. "\n\n" .. _("Example:") .. "\n" .. self:storagePreview(current),
        buttons = {
            preset(_("Author / Title"), "{home}/{author:first}/{title}.{ext}"),
            preset(_("Author / Series / Title"), "{home}/{author:first}/{series}/{title}.{ext}"),
            preset(_("Library / Author / Title"), "{home}/{library}/{author:first}/{title}.{ext}"),
            preset(_("All books in Home"), "{home}/{title}.{ext}"),
            { { text = _("Custom template…"), callback = function() UIManager:close(dialog); self:showCustomBookStorage() end } },
            { { text = _("Back"), callback = function() UIManager:close(dialog); self:showSettings() end } },
        },
    }
    UIManager:show(dialog)
end

function Libby:refreshBrowserSnapshot(browser)
    local wifi_on = type(NetworkMgr.isWifiOn) ~= "function" or NetworkMgr:isWifiOn()
    local connected = type(NetworkMgr.isConnected) ~= "function" or NetworkMgr:isConnected()
    if not (wifi_on and connected) then
        UIManager:show(InfoMessage:new{
            text = _("Wi-Fi is not available. Connect to Wi-Fi and try again."),
        })
        return false
    end

    browser.refresh_state = "refreshing"
    browser:updateItems()

    NetworkMgr:runWhenConnected(function()
        Trapper:wrap(function()
            local completed, encoded = Trapper:dismissableRunInSubprocess(function()
                local state = self.controller:sync_libby()
                if not state then return nil end
                local normalized = self.controller:normalize_libby_state(state)
                if not normalized then return nil end
                return rapidjson.encode(normalized)
            end, nil, true)
            if not completed or type(encoded) ~= "string" then
                UIManager:nextTick(function()
                    if not UIManager:isWidgetShown(browser) then return end
                    browser.refresh_state = "failed"
                    browser:updateItems()
                end)
                return
            end

            local ok, refreshed = pcall(rapidjson.decode, encoded)
            if not ok or type(refreshed) ~= "table" or not self.controller:save_libby_snapshot(refreshed) then
                UIManager:nextTick(function()
                    if not UIManager:isWidgetShown(browser) then return end
                    browser.refresh_state = "failed"
                    browser:updateItems()
                end)
                return
            end

            UIManager:nextTick(function()
                if not UIManager:isWidgetShown(browser) then return end
                self.controller:reconcile_downloaded_loans(refreshed, function(path)
                    self:removeTrackedBook(path)
                end)
                browser:refreshSnapshot(refreshed, "live")
                self:prefetchBrowserCovers(browser)
            end)
        end)
    end)
end

function Libby:showBrowser()
    if self.catalog_browser ~= nil then return end

    self.catalog_browser = LibbyCatalog:new{
        snapshot = self.controller:cached_libby_snapshot() or {},
        settings = self.controller.settings,
        _manager = self,
        download_callback = function(loan)
            self:downloadLoan(loan)
        end,
        network_available_callback = function()
            local wifi_on = type(NetworkMgr.isWifiOn) ~= "function" or NetworkMgr:isWifiOn()
            local connected = type(NetworkMgr.isConnected) ~= "function" or NetworkMgr:isConnected()
            return wifi_on and connected
        end,
        cover_path_callback = function(loan)
            return self:coverCachePath(loan)
        end,
        selection_changed_callback = function()
            self.controller:save()
        end,
        refresh_callback = function()
            self:refreshBrowserSnapshot(self.catalog_browser)
        end,
        settings_callback = function()
            self:showSettings()
        end,
        close_callback = function()
            UIManager:close(self.catalog_browser)
            self.catalog_browser = nil
        end,
    }
    UIManager:show(self.catalog_browser)
    self:prefetchBrowserCovers(self.catalog_browser)

    local wifi_on = type(NetworkMgr.isWifiOn) ~= "function" or NetworkMgr:isWifiOn()
    local connected = type(NetworkMgr.isConnected) ~= "function" or NetworkMgr:isConnected()
    if wifi_on and connected and self.controller:libby_authenticated() then
        self:refreshBrowserSnapshot(self.catalog_browser)
    end

    if not self.controller:adobe_registered() then
        NetworkMgr:runWhenConnected(function()
            if not self.controller:adobe_registered() then
                self.controller:ensure_adobe_registration()
            end
        end)
    end
end

function Libby:showLibbySettings()
    local dialog
    local authenticated = self.controller:libby_authenticated()
    dialog = ButtonDialog:new{
        title = _("Libby Setup") .. "\n" .. (authenticated and _("Status: authenticated") or _("Status: not authenticated")),
        buttons = {
            { { text = authenticated and _("Authenticate another device") or _("Authentication"), callback = function()
                UIManager:close(dialog)
                self:showLibbySetup()
            end } },
            { { text = _("Reset"), callback = function()
                UIManager:close(dialog)
                UIManager:show(ConfirmBox:new{
                    text = _("Reset Libby authentication on this device?\n\nThis clears the saved Libby identity and cached library snapshot. Adobe registration is not changed."),
                    cancel_text = _("Cancel"),
                    ok_text = _("Reset"),
                    ok_callback = function()
                        local ok, err = self.controller:reset_libby_credentials()
                        if not ok then
                            UIManager:show(InfoMessage:new{ text = _("Could not reset Libby authentication:") .. "\n\n" .. tostring(err) })
                            return
                        end
                        if self.catalog_browser and UIManager:isWidgetShown(self.catalog_browser) then
                            self.catalog_browser:refreshSnapshot({}, nil)
                        end
                        UIManager:show(InfoMessage:new{ text = _("Libby authentication reset.") })
                    end,
                })
            end } },
            { { text = _("Back"), callback = function() UIManager:close(dialog); self:showSettings() end } },
        },
    }
    UIManager:show(dialog)
end

function Libby:showByteBooksLogin()
    NetworkMgr:runWhenConnected(function()
        local methods, methods_err = self.controller:adobe_sign_in_methods()
        if not methods then
            UIManager:show(InfoMessage:new{
                text = _("Could not query Adobe/ByteBooks sign-in methods:") .. "\n\n" .. tostring(methods_err),
            })
            return
        end

        local named_method
        local advertised = {}
        for _, candidate in ipairs(methods) do
            local method = candidate.method
            local name = candidate.name or method or _("Unknown")
            table.insert(advertised, tostring(name) .. (method and (" [" .. tostring(method) .. "]") or ""))
            if not named_method and type(method) == "string" and method ~= "" and method:lower() ~= "anonymous" then
                named_method = method
            end
        end
        if not named_method then
            UIManager:show(InfoMessage:new{
                text = _("The authentication service did not advertise a named-account sign-in method.")
                    .. "\n\n" .. _("Advertised methods:") .. "\n" .. table.concat(advertised, "\n"),
            })
            return
        end

        local dialog
        dialog = MultiInputDialog:new{
            title = _("ByteBooks Account"),
            description = _("Sign in with the email used for your Adobe ID and your ByteBooks password.")
                .. "\n\n" .. _("Server sign-in method:") .. " " .. named_method
                .. "\n" .. _("Your password is used only for this sign-in and is not saved."),
            fields = {
                { hint = _("Email") },
                { hint = _("ByteBooks password"), text_type = "password" },
            },
            buttons = {
                {
                    {
                        text = _("Cancel"),
                        id = "close",
                        callback = function() UIManager:close(dialog) end,
                    },
                    {
                        text = _("Sign in"),
                        is_enter_default = true,
                        callback = function()
                            local email, password = unpack(dialog:getFields())
                            email = koUtil.trim(email or "")
                            if email == "" or type(password) ~= "string" or password == "" then
                                UIManager:show(InfoMessage:new{
                                    text = _("Please enter your ByteBooks email and password."),
                                    timeout = 2,
                                })
                                return
                            end
                            UIManager:close(dialog)
                            UIManager:show(InfoMessage:new{ text = _("Signing in to ByteBooks..."), timeout = 1 })
                            local registered, err = self.controller:create_adobe_account_registration(email, password, named_method)
                            password = nil
                            UIManager:show(InfoMessage:new{
                                text = registered
                                    and (_("ByteBooks authorization created successfully.")
                                        .. "\n\n" .. _("Account:") .. " " .. tostring(registered.username or email)
                                        .. "\n" .. _("ADEPT user:") .. " " .. tostring(registered.user or ""))
                                    or (_("ByteBooks sign-in failed:") .. "\n\n" .. tostring(err)),
                            })
                        end,
                    },
                },
            },
        }
        UIManager:show(dialog)
        dialog:onShowKeyboard()
    end)
end

function Libby:showAdobeSettings()
    local dialog
    local summary = self.controller:adobe_summary()
    local status_text = _("Status: not registered")
    if summary.registered then
        if summary.authorizationType == "account" then
            status_text = _("Status: ByteBooks account")
            if summary.username then status_text = status_text .. "\n" .. tostring(summary.username) end
        else
            status_text = _("Status: anonymous authorization")
        end
    end
    dialog = ButtonDialog:new{
        title = _("Adobe Setup") .. "\n" .. status_text,
        buttons = {
            { { text = _("Register device (anonymous)"), callback = function()
                UIManager:close(dialog)
                NetworkMgr:runWhenConnected(function()
                    local registered, err = self.controller:create_adobe_registration()
                    UIManager:show(InfoMessage:new{
                        text = registered and _("Anonymous Adobe registration created successfully.")
                            or (_("Could not create Adobe registration:") .. "\n\n" .. tostring(err)),
                    })
                end)
            end } },
            { { text = _("Sign in with ByteBooks account"), callback = function()
                UIManager:close(dialog)
                self:showByteBooksLogin()
            end } },
            { { text = _("Adobe Status"), callback = function()
                UIManager:close(dialog)
                self:showStatus()
            end } },
            { { text = _("Export authorization"), callback = function()
                local path, err = self.controller:export_adobe_registration()
                UIManager:show(InfoMessage:new{
                    text = path and (_("Adobe authorization exported to:") .. "\n\n" .. path
                        .. "\n\n" .. _("Treat this file as a private credential."))
                        or (_("Could not export Adobe authorization:") .. "\n\n" .. tostring(err)),
                })
            end } },
            { { text = _("Import authorization"), callback = function()
                local path = self.controller:adobe_export_path()
                UIManager:show(ConfirmBox:new{
                    text = _("Import Adobe authorization from:") .. "\n\n" .. path
                        .. "\n\n" .. _("This replaces the Adobe authorization currently used by Libby."),
                    cancel_text = _("Cancel"),
                    ok_text = _("Import"),
                    ok_callback = function()
                        local imported, err = self.controller:import_adobe_registration(path)
                        UIManager:show(InfoMessage:new{
                            text = imported and _("Adobe authorization imported successfully.")
                                or (_("Could not import Adobe authorization:") .. "\n\n" .. tostring(err)),
                        })
                    end,
                })
            end } },
            { { text = _("Reset"), callback = function()
                UIManager:close(dialog)
                UIManager:show(ConfirmBox:new{
                    text = _("Reset the saved Adobe registration on this device?"),
                    cancel_text = _("Cancel"),
                    ok_text = _("Reset"),
                    ok_callback = function()
                        local ok, err = self.controller:reset_adobe_registration()
                        UIManager:show(InfoMessage:new{
                            text = ok and _("Adobe registration reset.")
                                or (_("Could not reset Adobe registration:") .. "\n\n" .. tostring(err)),
                        })
                    end,
                })
            end } },
            { { text = _("Back"), callback = function() UIManager:close(dialog); self:showSettings() end } },
        },
    }
    UIManager:show(dialog)
end

function Libby:showShelfLayoutSettings(original_columns, original_rows, columns, rows)
    original_columns = original_columns or tonumber(self.controller.settings.libby_shelf_columns) or 4
    original_rows = original_rows or tonumber(self.controller.settings.libby_shelf_rows) or 2
    columns = math.max(2, math.min(8, tonumber(columns) or original_columns))
    rows = math.max(1, math.min(5, tonumber(rows) or original_rows))

    local function preview(next_columns, next_rows)
        if self.catalog_browser and UIManager:isWidgetShown(self.catalog_browser) then
            self.catalog_browser:setShelfLayout(next_columns, next_rows)
        else
            self.controller.settings.libby_shelf_columns = next_columns
            self.controller.settings.libby_shelf_rows = next_rows
        end
    end

    local dialog
    local function change(next_columns, next_rows)
        UIManager:close(dialog)
        preview(next_columns, next_rows)
        self:showShelfLayoutSettings(original_columns, original_rows, next_columns, next_rows)
    end

    dialog = ButtonDialog:new{
        title = _("Shelf size") .. "\n" .. string.format(_("%d columns × %d rows"), columns, rows),
        buttons = {
            {
                { text = "−", enabled = columns > 2, callback = function() change(columns - 1, rows) end },
                { text = string.format(_("Columns: %d"), columns), enabled = false },
                { text = "+", enabled = columns < 8, callback = function() change(columns + 1, rows) end },
            },
            {
                { text = "−", enabled = rows > 1, callback = function() change(columns, rows - 1) end },
                { text = string.format(_("Rows: %d"), rows), enabled = false },
                { text = "+", enabled = rows < 5, callback = function() change(columns, rows + 1) end },
            },
            {
                { text = _("Cancel"), callback = function()
                    UIManager:close(dialog)
                    preview(original_columns, original_rows)
                    self.controller:save()
                    self:showSettings()
                end },
                { text = _("Accept"), callback = function()
                    UIManager:close(dialog)
                    preview(columns, rows)
                    self.controller:save()
                    self:showSettings()
                end },
            },
        },
    }
    UIManager:show(dialog)
end

function Libby:showSettings()
    local dialog
    dialog = ButtonDialog:new{
        title = _("Libby Settings"),
        buttons = {
            { { text = _("Libby Setup"), callback = function() UIManager:close(dialog); self:showLibbySettings() end } },
            { { text = _("Adobe Setup"), callback = function() UIManager:close(dialog); self:showAdobeSettings() end } },
            { { text = _("Shelf size"), callback = function() UIManager:close(dialog); self:showShelfLayoutSettings() end } },
            { { text = _("Book Storage"), callback = function() UIManager:close(dialog); self:showBookStorageSettings() end } },
            { { text = _("Close"), callback = function() UIManager:close(dialog) end } },
        },
    }
    UIManager:show(dialog)
end

function Libby:addToMainMenu(menu_items)
    menu_items.libby = {
        text = _("Libby"),
        sorting_hint = "tools",
        callback = function() self:showBrowser() end,
        legacy_sub_item_table = {
            {
                text = _("Loans"),
                callback = function() self:showLoans() end,
            },
            {
                text = _("Library cards"),
                callback = function() self:showLibraryCards() end,
            },
            {
                text = _("Test Libby connection"),
                callback = function() self:testConnection() end,
            },
            {
                text = _("Status"),
                callback = function() self:showStatus() end,
                separator = true,
            },
            {
                text = _("Settings"),
                sub_item_table = {
                    {
                        text = _("Libby Setup"),
                        callback = function() self:showLibbySetup() end,
                    },
                    {
                        text = _("Adobe Setup"),
                        callback = function() self:showAdobeSettings() end,
                    },
                    {
                        text = _("Shelf size"),
                        callback = function() self:showShelfLayoutSettings() end,
                    },
                    {
                        text = _("Book Storage"),
                        callback = function() self:showBookStorageSettings() end,
                    },
                },
            },
        },
    }
end

return Libby
