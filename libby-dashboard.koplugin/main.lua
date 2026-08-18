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
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local Geom = require("ui/geometry")
local InfoMessage = require("ui/widget/infomessage")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local TopContainer = require("ui/widget/container/topcontainer")
local TextViewer = require("ui/widget/textviewer")
local NetworkMgr = require("ui/network/manager")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local rapidjson = require("rapidjson")
local lfs = require("libs/libkoreader-lfs")
local util = require("ffi/util")
local sha2 = require("ffi/sha2")
local koUtil = require("util")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local DiagnosticLog = require("diagnostic_log")
local ExternalAcsm = require("external_acsm")
local KOReaderController = require("koreader_controller")
local KOReaderTransport = require("koreader_transport")
local LibbyCatalog = require("libby_catalog")
local LoanModel = require("loan_model")
local NetworkAction = require("network_action")
local RefreshWatchdog = require("refresh_watchdog")
local PathTemplate = require("path_template")

local PluginMeta = dofile(plugin_root .. "/_meta.lua")
local PLUGIN_VERSION = assert(PluginMeta.version, "Missing plugin version in _meta.lua")
local DEV_MODE_ON_SHA256 = "2a3ce23f23f4f9a2f6e1a1b3f7cea2f78a5d815c934fa2c38c645f5fa64a8212"
local DEV_MODE_OFF_SHA256 = "ac009e462f23deafd26600296e2ee50fe6f640c43d8323fd0bd668914a14df22"

local TopAlignedMultiInputDialog = MultiInputDialog:extend{}
function TopAlignedMultiInputDialog:init(reinit)
    MultiInputDialog.init(self, reinit)
    local keyboard_height = self.keyboard_visible and self._input_widget:getKeyboardDimen().h or 0
    local available = Geom:new{ w = self.screen_width, h = self.screen_height - keyboard_height }
    local dialog_h = self.dialog_frame:getSize().h
    self[1] = TopContainer:new{
        dimen = available,
        CenterContainer:new{
            dimen = Geom:new{ w = available.w, h = dialog_h },
            self.dialog_frame,
        },
    }
end

local TopAlignedButtonDialog = ButtonDialog:extend{}
function TopAlignedButtonDialog:init()
    ButtonDialog.init(self)
    local screen = Device.screen:getSize()
    local dialog_h = self.movable:getSize().h
    self[1] = TopContainer:new{
        dimen = screen,
        CenterContainer:new{
            dimen = Geom:new{ w = screen.w, h = dialog_h },
            self.movable,
        },
    }
end

-- Load the vendored Adobe stack while PluginLoader still has this plugin's
-- temporary package.path active. KOReader restores package.path after main.lua
-- returns, so lazy-loading these modules later would lose dependencies/?.lua.
require("adobe.adobe")
require("adobe.fulfillment")

local LibbyDashboard = WidgetContainer:extend{
    name = "libby-dashboard",
    fullname = _("Libby Dashboard"),
}

LibbyDashboard.PLUGIN_VERSION = PLUGIN_VERSION

function LibbyDashboard:runNetworkAction(callback, require_online)
    return NetworkAction.run(self, NetworkMgr, UIManager, callback, require_online)
end

local function truncateUtf8Bytes(text, max_bytes)
    if #text <= max_bytes then return text end
    local cut = math.max(0, max_bytes)
    while cut > 0 and text:byte(cut + 1) and text:byte(cut + 1) >= 128 and text:byte(cut + 1) < 192 do
        cut = cut - 1
    end
    return text:sub(1, cut)
end

local function safeDisplayText(value, max_bytes)
    local text = tostring(value or "")
    text = text:gsub("[%z-W]", " "):gsub("%s+", " ")
    max_bytes = max_bytes or 96
    if #text > max_bytes then
        text = truncateUtf8Bytes(text, math.max(1, max_bytes - 3)) .. "..."
    end
    return text
end

function LibbyDashboard:init()
    DiagnosticLog.init()
    DiagnosticLog.log("[plugin] init:start", "version=" .. tostring(PLUGIN_VERSION))
    local settings_dir = DataStorage:getSettingsDir() .. "/libby-dashboard"
    koUtil.makePath(settings_dir)
    self.settings_file = settings_dir .. "/libby-dashboard.lua"
    self.settings_store = LuaSettings:open(self.settings_file)
    self.controller = KOReaderController.new{
        reader_settings = G_reader_settings,
        settings_store = self.settings_store,
        device = Device,
    }
    self.controller:load()
    DiagnosticLog.log("[plugin] controller:loaded")
    local CreDocument = require("document/credocument")
    local ProtectedEpub = require("protected_epub")
    ProtectedEpub.install(CreDocument, function()
        return self.controller.settings
    end)
    DiagnosticLog.log("[plugin] protected-epub:installed")
    self:registerAcsmProvider()
    DiagnosticLog.log("[plugin] acsm-provider:registered")
    self.ui.menu:registerToMainMenu(self)
    DiagnosticLog.log("[plugin] init:complete")
end

function LibbyDashboard:closeCatalogBrowser(full_refresh)
    NetworkAction.release(self, NetworkMgr, UIManager)
    RefreshWatchdog.cancel(self, UIManager)
    if self.catalog_refresh_tick then
        UIManager:unschedule(self.catalog_refresh_tick)
        self.catalog_refresh_tick = nil
    end
    if self.catalog_browser then
        UIManager:close(self.catalog_browser)
        self.catalog_browser = nil
    end
    if full_refresh then
        UIManager:setDirty(nil, "full")
    end
end

function LibbyDashboard:onExit()
    self:closeCatalogBrowser(true)
end

function LibbyDashboard:onCloseWidget()
    self:closeCatalogBrowser(false)
end

function LibbyDashboard:registerAcsmProvider()
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

function LibbyDashboard:isFileTypeSupported(file)
    return type(file) == "string" and koUtil.getFileNameSuffix(file):lower() == "acsm"
end

function LibbyDashboard:externalAcsmDestination(file, model, extension)
    model = type(model) == "table" and model or {}
    extension = extension or "epub"

    local fallbackTitle = tostring(file or ""):match("([^/]+)%.[Aa][Cc][Ss][Mm]$")
        or tostring(file or ""):match("([^/]+)$")
        or "External ACSM"
    if not model.title or model.title == "" then model.title = fallbackTitle end
    if not model.library or model.library == "" then model.library = "External ACSM" end

    local desired = self.controller:book_destination(model, extension)
    local parent = util.dirname(desired)
    if parent and parent ~= "" and not koUtil.makePath(parent) then
        return nil, "Could not create destination folder: " .. tostring(parent)
    end
    return desired
end

function LibbyDashboard:showExternalAcsmOverwrite(target, overwrite_callback, cancel_callback)
    DiagnosticLog.log("[acsm] overwrite-prompt", tostring(target or ""))
    UIManager:show(ConfirmBox:new{
        text = _("Book already found at:") .. "\n\n" .. tostring(target),
        cancel_text = _("Cancel"),
        ok_text = _("Overwrite"),
        cancel_callback = cancel_callback,
        ok_callback = overwrite_callback,
    })
end

function LibbyDashboard:finishExternalAcsm(file, outputPath)
    DiagnosticLog.log("[acsm] fulfillment-success", tostring(outputPath or ""))
    local removed, removeErr = os.remove(file)
    if not removed and koUtil.pathExists(file) then
        Trapper:reset()
        UIManager:show(InfoMessage:new{
            text = _("Book downloaded successfully, but the source ACSM could not be deleted:")
                .. "\n\n" .. tostring(file) .. "\n\n" .. tostring(removeErr or "unknown error"),
        })
        return
    end

    if self.ui and self.ui.file_chooser then self.ui.file_chooser:refreshPath() end
    Trapper:clear()
    if self.ui and type(self.ui.openFile) == "function" then
        UIManager:nextTick(function() self.ui:openFile(outputPath) end)
    else
        UIManager:show(InfoMessage:new{
            text = _("Book downloaded successfully:") .. "\n\n" .. tostring(outputPath),
        })
    end
end

function LibbyDashboard:fulfillExternalAcsm(file, EpubMetadata, acsmMetadata, approvedTarget)
    DiagnosticLog.log("[acsm] fulfillment:start")
    self:runNetworkAction(function()
        Trapper:wrap(function()
        Trapper:info(_("Downloading book..."), false, true)
        local replacementTarget
        local stagingPath
        local requireFinalConfirmation = false

        local result, fulfill_err = self.controller:fulfill_acsm(file, nil, {
            resolve_output_path = function(downloadedPath, format)
                local downloadedMetadata = {}
                if format and format.is_epub then
                    downloadedMetadata = EpubMetadata.fromEpub(downloadedPath) or {}
                end
                local model = EpubMetadata.merge(downloadedMetadata, acsmMetadata)
                local desired, destinationErr = self:externalAcsmDestination(
                    file, model, format and format.extension or "epub"
                )
                if not desired then return nil, destinationErr end

                if ExternalAcsm.pathOccupied(desired) then
                    replacementTarget = desired
                    stagingPath, destinationErr = ExternalAcsm.stagingPath(desired)
                    if not stagingPath then return nil, destinationErr end
                    requireFinalConfirmation = approvedTarget ~= desired
                    return stagingPath
                end
                return desired
            end,
        })

        if not result then
            if stagingPath then ExternalAcsm.cleanup(stagingPath) end
            Trapper:reset()
            UIManager:show(InfoMessage:new{
                text = _("ACSM processing failed:") .. "\n\n" .. tostring(fulfill_err),
            })
            return
        end

        local function finalizeReplacement()
            local installed, replaceErr = ExternalAcsm.replace(stagingPath, replacementTarget)
            if not installed then
                ExternalAcsm.cleanup(stagingPath)
                Trapper:reset()
                UIManager:show(InfoMessage:new{
                    text = _("Could not overwrite existing book:") .. "\n\n" .. tostring(replaceErr),
                })
                return
            end
            self:finishExternalAcsm(file, installed)
        end

        if replacementTarget then
            if requireFinalConfirmation then
                Trapper:reset()
                self:showExternalAcsmOverwrite(
                    replacementTarget,
                    finalizeReplacement,
                    function() ExternalAcsm.cleanup(stagingPath) end
                )
                return
            end
            finalizeReplacement()
            return
        end

        self:finishExternalAcsm(file, result.outputPath)
        end)
    end)
end

function LibbyDashboard:openFile(file)
    DiagnosticLog.log("[acsm] open:start", tostring(file or ""))
    if not self:isFileTypeSupported(file) then return end

    self:runNetworkAction(function()
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

        local metadata_ok, EpubMetadata = pcall(require, "epub_metadata")
        if not metadata_ok then
            EpubMetadata = {
                fromAcsm = function() return {} end,
                fromEpub = function() return {} end,
                merge = function(primary, fallback)
                    local result = {}
                    for key, value in pairs(fallback or {}) do result[key] = value end
                    for key, value in pairs(primary or {}) do result[key] = value end
                    return result
                end,
            }
        end
        local acsmMetadata = EpubMetadata.fromAcsm(file) or {}
        local preflightPath, destinationErr = self:externalAcsmDestination(file, acsmMetadata, "epub")
        if not preflightPath then
            Trapper:reset()
            UIManager:show(InfoMessage:new{
                text = _("Could not determine book destination:") .. "\n\n" .. tostring(destinationErr),
            })
            return
        end

        local function startFulfillment(approvedTarget)
            UIManager:nextTick(function()
                self:fulfillExternalAcsm(file, EpubMetadata, acsmMetadata, approvedTarget)
            end)
        end

        Trapper:clear()
        if ExternalAcsm.pathOccupied(preflightPath) then
            self:showExternalAcsmOverwrite(
                preflightPath,
                function() startFulfillment(preflightPath) end,
                function() end
            )
            return
        end
        startFulfillment(nil)
        end)
    end)
end

function LibbyDashboard:showStatus()
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

function LibbyDashboard:showPending(feature)
    UIManager:show(InfoMessage:new{
        text = feature .. "\n\n" .. _("The KOReader network/UI adapter is still being connected to the tested Libby core."),
    })
end

function LibbyDashboard:showLibraryCards()
    self:runNetworkAction(function()
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

local function removeTree(path)
    local attr = lfs.attributes(path)
    if not attr then return true end
    if attr.mode ~= "directory" then return os.remove(path) end
    for name in lfs.dir(path) do
        if name ~= "." and name ~= ".." and not removeTree(path .. "/" .. name) then return nil end
    end
    return lfs.rmdir(path)
end

local function copyTree(source, destination)
    local attr = lfs.attributes(source)
    if not attr then return nil end
    if attr.mode ~= "directory" then return util.copyFile(source, destination) ~= nil end
    if not koUtil.makePath(destination) then return nil end
    for name in lfs.dir(source) do
        if name ~= "." and name ~= ".." and not copyTree(source .. "/" .. name, destination .. "/" .. name) then return nil end
    end
    return true
end

local function moveTree(source, destination)
    if not lfs.attributes(source) then return true end
    removeTree(destination)
    local parent = util.dirname(destination)
    if parent and parent ~= "" and not koUtil.makePath(parent) then return nil end
    if os.rename(source, destination) then return true end
    if not copyTree(source, destination) then return nil end
    return removeTree(source)
end

function LibbyDashboard:historyDir()
    return DataStorage:getSettingsDir() .. "/libby-dashboard/history"
end

function LibbyDashboard:historySidecarPath(loan_id)
    if loan_id == nil then return nil end
    return self:historyDir() .. "/" .. tostring(loan_id):gsub("[^%w%._%-]", "_") .. ".sdr"
end

function LibbyDashboard:restoreReadingHistory(loan, path)
    local history = self:historySidecarPath(loan and loan.id)
    if not history or not lfs.attributes(history) then return true end
    return moveTree(history, DocSettings:getSidecarDir(path))
end

function LibbyDashboard:pruneEmptyBookFolders(path)
    DiagnosticLog.log("[cleanup] prune:root:start")
    local home = self.controller.reader_settings:readSetting("home_dir")
    local root = home
    if type(home) == "string" and home ~= "" and type(path) == "string"
        and path:sub(1, #home + 1) == home .. "/" then
        local relative = path:sub(#home + 2)
        local top_level = relative:match("^([^/]+)")
        if top_level and top_level ~= "" then root = home .. "/" .. top_level end
    end
    DiagnosticLog.log("[cleanup] prune:root:end", tostring(root or ""))

    DiagnosticLog.log("[cleanup] prune:dirname:start", tostring(path or ""))
    local dir = util.dirname(path)
    DiagnosticLog.log("[cleanup] prune:dirname:end", tostring(dir or ""))

    while dir and dir ~= "" and dir ~= root and dir:sub(1, #root + 1) == root .. "/" do
        DiagnosticLog.log("[cleanup] prune:dir:start", dir)
        local empty = true
        DiagnosticLog.log("[cleanup] prune:attributes:start", dir)
        local dir_attr = lfs.attributes(dir)
        DiagnosticLog.log("[cleanup] prune:attributes:end", "exists=" .. tostring(dir_attr ~= nil) .. " mode=" .. tostring(dir_attr and dir_attr.mode or ""))
        if not dir_attr or dir_attr.mode ~= "directory" then
            DiagnosticLog.log("[cleanup] prune:stop-missing", dir)
            break
        end
        DiagnosticLog.log("[cleanup] prune:lfs-dir:start", dir)
        local iterator, dir_obj = lfs.dir(dir)
        DiagnosticLog.log("[cleanup] prune:lfs-dir:end", "iterator=" .. tostring(iterator ~= nil))
        if iterator then
            for name in iterator, dir_obj do
                DiagnosticLog.log("[cleanup] prune:entry", tostring(name))
                if name ~= "." and name ~= ".." then empty = false break end
            end
        end
        DiagnosticLog.log("[cleanup] prune:scan:end", "empty=" .. tostring(empty))
        if not empty then
            DiagnosticLog.log("[cleanup] prune:stop-not-empty", dir)
            break
        end

        DiagnosticLog.log("[cleanup] prune:rmdir:start", dir)
        local removed, remove_err = lfs.rmdir(dir)
        DiagnosticLog.log("[cleanup] prune:rmdir:end", "ok=" .. tostring(removed ~= nil) .. " error=" .. tostring(remove_err or ""))
        if not removed then break end

        DiagnosticLog.log("[cleanup] prune:parent:start", dir)
        dir = util.dirname(dir)
        DiagnosticLog.log("[cleanup] prune:parent:end", tostring(dir or ""))
    end
    DiagnosticLog.log("[cleanup] prune:end")
end

function LibbyDashboard:removeTrackedBook(record)
    DiagnosticLog.log("[cleanup] removeTrackedBook:start", "record_type=" .. type(record))
    local path = type(record) == "table" and record.path or record
    DiagnosticLog.log("[cleanup] path:resolved", tostring(path or ""))
    if type(path) ~= "string" or path == "" then
        DiagnosticLog.log("[cleanup] path:invalid")
        return
    end

    local loan_id = type(record) == "table" and record.loan_id or nil
    DiagnosticLog.log("[cleanup] loan-id:resolved", tostring(loan_id or ""))

    DiagnosticLog.log("[cleanup] sidecar:get:start", path)
    local sidecar = DocSettings:getSidecarDir(path)
    DiagnosticLog.log("[cleanup] sidecar:get:end", tostring(sidecar or ""))

    DiagnosticLog.log("[cleanup] history-path:start")
    local history = self:historySidecarPath(loan_id)
    DiagnosticLog.log("[cleanup] history-path:end", tostring(history or ""))

    DiagnosticLog.log("[cleanup] sidecar:attributes:start", tostring(sidecar or ""))
    local sidecar_attributes = sidecar and lfs.attributes(sidecar) or nil
    DiagnosticLog.log("[cleanup] sidecar:attributes:end", "exists=" .. tostring(sidecar_attributes ~= nil))

    if history and sidecar_attributes then
        DiagnosticLog.log("[cleanup] history-dir:create:start")
        local history_dir_ok = koUtil.makePath(self:historyDir())
        DiagnosticLog.log("[cleanup] history-dir:create:end", "ok=" .. tostring(history_dir_ok ~= false))

        DiagnosticLog.log("[cleanup] sidecar:move:start", tostring(sidecar) .. " -> " .. tostring(history))
        local moved = moveTree(sidecar, history)
        DiagnosticLog.log("[cleanup] sidecar:move:end", "ok=" .. tostring(moved ~= false))
        if not moved then return false end
    else
        DiagnosticLog.log("[cleanup] sidecar:move:skip", "history=" .. tostring(history ~= nil) .. " sidecar=" .. tostring(sidecar_attributes ~= nil))
    end

    DiagnosticLog.log("[cleanup] book:remove:start", path)
    local removed, remove_err = os.remove(path)
    DiagnosticLog.log("[cleanup] book:remove:end", "ok=" .. tostring(removed ~= nil) .. " error=" .. tostring(remove_err or ""))

    DiagnosticLog.log("[cleanup] folders:prune:start", path)
    self:pruneEmptyBookFolders(path)
    DiagnosticLog.log("[cleanup] folders:prune:end")
    DiagnosticLog.log("[cleanup] removeTrackedBook:end")
    return true
end

function LibbyDashboard:downloadLoan(loan)
    DiagnosticLog.log("[loan] download:requested")
    if not loan or not loan.adobe_format then
        local kind = loan and loan.media_type
        local message = kind == "audiobook" and _("Audiobooks are not currently supported by the Libby plugin.")
            or kind == "magazine" and _("Magazines are not currently supported by the Libby plugin.")
            or _("This loan has no supported Adobe EPUB/PDF format.")
        UIManager:show(InfoMessage:new{ text = message })
        return
    end


    self:runNetworkAction(function()
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

        Trapper:info(_("Downloading and preparing book…\n\nThis may take a few minutes."), false, true)
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
        self:restoreReadingHistory(loan, downloaded_path)
        self.controller:track_downloaded_loan(loan, downloaded_path)
        Trapper:clear()
        if self.catalog_browser and UIManager:isWidgetShown(self.catalog_browser) then
            self.catalog_browser:updateItems()
        end
        UIManager:show(InfoMessage:new{ text = _("Book downloaded successfully:") .. "\n\n" .. tostring(downloaded_path) })
        end)
    end)
end

function LibbyDashboard:showLoanDetails(loan)
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
    table.insert(lines, _("Format: ") .. tostring(loan.adobe_format or loan.non_adobe_format_label or loan.media_type or _("Unsupported")))
    local dialog
    local buttons = {}
    local downloaded = self.controller:downloaded_loan(loan.id)
    local local_path = type(downloaded) == "table" and downloaded.path or nil
    if type(local_path) == "string" and koUtil.pathExists(local_path) then
        table.insert(buttons, { { text = _("Open"), callback = function()
            UIManager:close(dialog)
            if self.ui and type(self.ui.openFile) == "function" then
                UIManager:nextTick(function() self.ui:openFile(local_path) end)
            end
        end } })
    elseif loan.adobe_format then
        table.insert(buttons, { { text = _("Download"), callback = function()
            UIManager:close(dialog)
            self:downloadLoan(loan)
        end } })
    end
    table.insert(buttons, { { text = _("Close"), callback = function() UIManager:close(dialog) end } })
    dialog = ButtonDialog:new{ title = table.concat(lines, "\n"), buttons = buttons }
    UIManager:show(dialog)
end

function LibbyDashboard:showLoans()
    self:runNetworkAction(function()
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

function LibbyDashboard:testConnection()
    self:runNetworkAction(function()
        local ok, err = self.controller:test_libby_connection()
        UIManager:show(InfoMessage:new{
            text = ok and _("Libby connection successful. KOReader reached the Libby service and received a valid chip response.")
                or (_("Libby connection failed:") .. "\n\n" .. tostring(err)),
        })
    end)
end

function LibbyDashboard:showLibbySetup()
    UIManager:show(ConfirmBox:new{
        text = _("On an already signed-in Libby device, open:\n\nMenu → Copy To Another Device → Enter Setup Code\n\nThe setup code is valid for only 60 seconds. Have that screen ready before generating the code."),
        cancel_text = _("Cancel"),
        ok_text = _("Generate code"),
        ok_callback = function() self:generateLibbySetupCode() end,
    })
end

function LibbyDashboard:generateLibbySetupCode()
    self:runNetworkAction(function()
        local setup, err = self.controller:begin_libby_setup()
    if not setup then
        UIManager:show(InfoMessage:new{ text = _("Could not generate Libby setup code:") .. string.char(10, 10) .. tostring(err) })
        return
    end
        self:showLibbySetupCountdown()
    end)
end

function LibbyDashboard:showLibbySetupCountdown()
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

function LibbyDashboard:verifyLibbySetupCode()
    self:runNetworkAction(function()
        local waiting_message = InfoMessage:new{ text = _("Awaiting Libby verification...") }
        UIManager:show(waiting_message)
        UIManager:forceRePaint()
        local state, err = self.controller:complete_libby_setup()
        UIManager:close(waiting_message)
        UIManager:forceRePaint()
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
                .. _("Current loans found: ") .. tostring(#(state.loans or {})) .. "\n\n"
                .. _("Account Backup is recommended so this Libby authentication can be restored later."),
        })
        if self.catalog_browser and UIManager:isWidgetShown(self.catalog_browser) then
            self:refreshBrowserSnapshot(self.catalog_browser)
        end
    end)
end

function LibbyDashboard:offerLibbySetupRegeneration()
    UIManager:show(ConfirmBox:new{
        text = _("The 60-second Libby setup code has expired."),
        cancel_text = _("Cancel"),
        ok_text = _("Generate another"),
        ok_callback = function() self:generateLibbySetupCode() end,
    })
end

function LibbyDashboard:coverCacheDir()
    return DataStorage:getDataDir() .. "/cache/libby-dashboard/covers"
end

function LibbyDashboard:coverCachePath(loan)
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

function LibbyDashboard:prefetchBrowserCovers(browser)
    local snapshot = browser and browser.snapshot or nil
    if type(snapshot) ~= "table" or type(snapshot.loans) ~= "table" then return end
    local missing = {}
    for _, loan in ipairs(snapshot.loans) do
        if loan.cover_url and not self:coverCachePath(loan) then table.insert(missing, loan) end
    end
    if #missing == 0 then return end

    local online = type(NetworkMgr.isOnline) ~= "function" or NetworkMgr:isOnline()
    if not online then return end

    self:runNetworkAction(function()
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

function LibbyDashboard:storagePreview(template)
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

function LibbyDashboard:applyBookPathTemplate(template)
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

function LibbyDashboard:showCustomBookStorage()
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

function LibbyDashboard:showBookStorageSettings()
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
            preset(_("Author / Series / Title"), PathTemplate.DEFAULT_TEMPLATE),
            preset(_("Library / Author / Title"), "{home}/{library}/{author:first}/{title}.{ext}"),
            preset(_("All books in Home"), "{home}/{title}.{ext}"),
            { { text = _("Custom template…"), callback = function() UIManager:close(dialog); self:showCustomBookStorage() end } },
            { { text = _("Back"), callback = function() UIManager:close(dialog); self:showSettings() end } },
        },
    }
    UIManager:show(dialog)
end

function LibbyDashboard:refreshBrowserSnapshot(browser)
    DiagnosticLog.log("[refresh] request")
    browser.refresh_state = "refreshing"
    DiagnosticLog.log("[refresh] ui:update-refreshing:start")
    browser:updateItems()
    DiagnosticLog.log("[refresh] ui:update-refreshing:end")

    local network_entered = false
    local network_watchdog
    network_watchdog = function()
        if network_entered then return end
        DiagnosticLog.log("[refresh] network-timeout", "online=" .. tostring(NetworkMgr:isOnline()))
        if not UIManager:isWidgetShown(browser) then return end
        browser.refresh_state = "failed"
        browser:updateItems()
        UIManager:show(InfoMessage:new{
            text = _("No online connection found.") .. string.char(10, 10)
                .. _("Refresh timed out; showing cached library data."),
            timeout = 5,
        })
    end
    local watchdog_token = RefreshWatchdog.arm(self, UIManager, network_watchdog)

    DiagnosticLog.log("[refresh] runWhenConnected:schedule")
    self:runNetworkAction(function()
        network_entered = true
        RefreshWatchdog.cancel(self, UIManager, watchdog_token)
        DiagnosticLog.log("[refresh] runWhenConnected:entered")
        Trapper:wrap(function()
            DiagnosticLog.log("[refresh] subprocess:start")
            local completed, encoded = Trapper:dismissableRunInSubprocess(function()
                local state = self.controller:sync_libby()
                if not state then return nil end
                local normalized = self.controller:normalize_libby_state(state)
                if not normalized then return nil end
                return rapidjson.encode(normalized)
            end, nil, true)
            DiagnosticLog.log("[refresh] subprocess:end",
                "completed=" .. tostring(completed) .. " encoded_type=" .. type(encoded))
            if not completed or type(encoded) ~= "string" then
                DiagnosticLog.log("[refresh] failure-nextTick:schedule", "stage=subprocess")
                UIManager:nextTick(function()
                    DiagnosticLog.log("[refresh] failure-nextTick:entered", "stage=subprocess")
                    if not UIManager:isWidgetShown(browser) then
                        DiagnosticLog.log("[refresh] failure-nextTick:browser-hidden", "stage=subprocess")
                        return
                    end
                    browser.refresh_state = "failed"
                    browser:updateItems()
                    DiagnosticLog.log("[refresh] failure-nextTick:complete", "stage=subprocess")
                end)
                return
            end

            DiagnosticLog.log("[refresh] decode:start")
            local ok, refreshed = pcall(rapidjson.decode, encoded)
            DiagnosticLog.log("[refresh] decode:end",
                "ok=" .. tostring(ok) .. " type=" .. type(refreshed))
            if not ok or type(refreshed) ~= "table" then
                DiagnosticLog.log("[refresh] failure-nextTick:schedule", "stage=decode")
                UIManager:nextTick(function()
                    DiagnosticLog.log("[refresh] failure-nextTick:entered", "stage=decode")
                    if not UIManager:isWidgetShown(browser) then
                        DiagnosticLog.log("[refresh] failure-nextTick:browser-hidden", "stage=decode")
                        return
                    end
                    browser.refresh_state = "failed"
                    browser:updateItems()
                    DiagnosticLog.log("[refresh] failure-nextTick:complete", "stage=decode")
                end)
                return
            end

            DiagnosticLog.log("[refresh] snapshot-save:start")
            local saved = self.controller:save_libby_snapshot(refreshed)
            DiagnosticLog.log("[refresh] snapshot-save:end", "saved=" .. tostring(saved ~= nil and saved ~= false))
            if not saved then
                DiagnosticLog.log("[refresh] failure-nextTick:schedule", "stage=save")
                UIManager:nextTick(function()
                    DiagnosticLog.log("[refresh] failure-nextTick:entered", "stage=save")
                    if not UIManager:isWidgetShown(browser) then
                        DiagnosticLog.log("[refresh] failure-nextTick:browser-hidden", "stage=save")
                        return
                    end
                    browser.refresh_state = "failed"
                    browser:updateItems()
                    DiagnosticLog.log("[refresh] failure-nextTick:complete", "stage=save")
                end)
                return
            end

            DiagnosticLog.log("[refresh] success-nextTick:schedule")
            UIManager:nextTick(function()
                DiagnosticLog.log("[refresh] success-nextTick:entered")
                if not UIManager:isWidgetShown(browser) then
                    DiagnosticLog.log("[refresh] success-nextTick:browser-hidden")
                    return
                end
                DiagnosticLog.log("[refresh] reconcile:start")
                self.controller:reconcile_downloaded_loans(refreshed, function(path)
                    DiagnosticLog.log("[refresh] reconcile:remove-book", tostring(path or ""))
                    self:removeTrackedBook(path)
                end)
                DiagnosticLog.log("[refresh] reconcile:end")
                DiagnosticLog.log("[refresh] browser-refresh:start")
                browser:refreshSnapshot(refreshed, "live")
                DiagnosticLog.log("[refresh] browser-refresh:end")
                DiagnosticLog.log("[refresh] cover-prefetch:start")
                self:prefetchBrowserCovers(browser)
                DiagnosticLog.log("[refresh] cover-prefetch:end")
                DiagnosticLog.log("[refresh] complete")
            end)
        end)
    end)
end

function LibbyDashboard:scheduleBrowserRefresh(browser)
    if self.catalog_refresh_tick then UIManager:unschedule(self.catalog_refresh_tick) end
    local tick
    tick = function()
        if browser ~= self.catalog_browser or not UIManager:isWidgetShown(browser) then
            if self.catalog_refresh_tick == tick then self.catalog_refresh_tick = nil end
            return
        end
        local online = type(NetworkMgr.isOnline) ~= "function" or NetworkMgr:isOnline()
        if online and self.controller:libby_authenticated()
                and browser.refresh_state ~= "refreshing" then
            self:refreshBrowserSnapshot(browser)
        end
        UIManager:scheduleIn(300, tick)
    end
    self.catalog_refresh_tick = tick
    UIManager:scheduleIn(300, tick)
end

function LibbyDashboard:returnLoan(loan)
    DiagnosticLog.log("[loan] return:requested")
    if type(loan) ~= "table" then return end
    if self.controller.settings.developer_mode == true then
        UIManager:show(InfoMessage:new{ text = _("Return is disabled while Developer Mode is enabled.") })
        return
    end
    local title = tostring(loan.title or _("this book"))
    UIManager:show(ConfirmBox:new{
        text = string.format(_("Return '%s' early?\n\nThis returns the loan to Libby and removes the downloaded book from this device. Reading history will be preserved."), title),
        ok_text = _("Return"),
        ok_callback = function()
            self:runNetworkAction(function()
            local ok, err = self.controller:return_loan(loan)
            if not ok then
                UIManager:show(InfoMessage:new{ text = _("Could not return loan: ") .. tostring(err or _("unknown error")) })
                return
            end
            if self.catalog_browser then self:refreshBrowserSnapshot(self.catalog_browser) end
            UIManager:show(InfoMessage:new{ text = _("Loan returned to Libby.") })
            end)
        end,
    })
end

function LibbyDashboard:showBrowser()
    DiagnosticLog.log("[ui] dashboard:open")
    if self.catalog_browser ~= nil then return end

    self.catalog_browser = LibbyCatalog:new{
        snapshot = self.controller:cached_libby_snapshot() or {},
        settings = self.controller.settings,
        _manager = self,
        download_callback = function(loan)
            self:downloadLoan(loan)
        end,
        return_callback = function(loan)
            self:returnLoan(loan)
        end,
        return_enabled = self.controller.settings.developer_mode ~= true,
        downloaded_path_callback = function(loan)
            local downloaded = self.controller:downloaded_loan(loan and loan.id)
            local path = type(downloaded) == "table" and downloaded.path or nil
            if type(path) == "string" and koUtil.pathExists(path) then return path end
            return nil
        end,
        open_callback = function(path)
            if self.ui and type(self.ui.openFile) == "function" then
                UIManager:nextTick(function() self.ui:openFile(path) end)
            end
        end,
        network_available_callback = function()
            return true
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
            self:closeCatalogBrowser(false)
        end,
    }
    UIManager:show(self.catalog_browser)
    self:scheduleBrowserRefresh(self.catalog_browser)
    self:runNetworkAction(function()
        if self.controller:libby_authenticated() then
            self:refreshBrowserSnapshot(self.catalog_browser)
        end
        if not self.controller:adobe_registered() then
            self.controller:ensure_adobe_registration()
        end
    end)
end

function LibbyDashboard:showAuthenticationSettings()
    local dialog
    dialog = ButtonDialog:new{
        title = _("Authentication"),
        buttons = {
            { { text = _("Libby Account"), callback = function() UIManager:close(dialog); self:showLibbySettings() end } },
            { { text = _("ByteBooks / Adobe Authorization"), callback = function() UIManager:close(dialog); self:showAdobeSettings() end } },
            { { text = _("Account Backup & Restore"), callback = function() UIManager:close(dialog); self:showAccountBackupSettings() end } },
            { { text = _("Back"), callback = function() UIManager:close(dialog); self:showSettings() end } },
        },
    }
    UIManager:show(dialog)
end

function LibbyDashboard:showAccountBackupSettings()
    local AccountBackup = require("account_backup")
    local NL = string.char(10)
    local dialog

    local function backupDisplayText(backup)
        local label = safeDisplayText(backup.label or _("Unlabeled Account Backup"), 72)
        local created = backup.created_at and backup.created_at:gsub("T", " "):gsub("Z$", " UTC") or _("Encrypted v1 backup")
        return label .. NL .. created .. " � " .. tostring(backup.location or "")
    end

    local function passwordDialog(importing, backup)
        local password_dialog
        local import_path = importing and backup and backup.path or nil
        local description
        local fields
        if importing then
            description = backupDisplayText(backup) .. NL .. NL .. tostring(import_path or "") .. NL .. NL
                .. _("Enter the password used when this encrypted backup was created.")
            fields = { { hint = _("Backup password"), text_type = "password" } }
        else
            description = _("Name: max 48 characters; filename uses the first 24.") .. NL
                .. _("Password: at least 8 characters and cannot be recovered.")
            fields = {
                { hint = _("Backup name (max 48 characters)") },
                { hint = _("Backup password"), text_type = "password" },
                { hint = _("Confirm password"), text_type = "password" },
            }
        end
        password_dialog = TopAlignedMultiInputDialog:new{
            title = importing and _("Restore Account Backup") or _("Create Account Backup"),
            description = description,
            fields = fields,
            buttons = { {
                { text = _("Cancel"), id = "close", callback = function() UIManager:close(password_dialog) end },
                { text = importing and _("Restore") or _("Export"), is_enter_default = true, callback = function()
                    local values = password_dialog:getFields()
                    local label
                    local password
                    if importing then
                        password = values and values[1] or ""
                    else
                        label = values and values[1] or ""
                        local normalized, label_err = AccountBackup.validate_label(label)
                        if not normalized then
                            UIManager:show(InfoMessage:new{ text = tostring(label_err) })
                            return
                        end
                        label = normalized
                        password = values and values[2] or ""
                        if password ~= (values and values[3] or "") then
                            UIManager:show(InfoMessage:new{ text = _("Backup passwords do not match.") })
                            return
                        end
                        if #password < 8 then
                            UIManager:show(InfoMessage:new{ text = _("Backup password must be at least 8 characters.") })
                            return
                        end
                    end
                    UIManager:close(password_dialog)
                    if importing then
                        local result, err = self.controller:import_account_backup(password, import_path)
                        if result then
                            local restored = {}
                            if result.libby then table.insert(restored, _("Libby authentication")) end
                            if result.adobe then table.insert(restored, _("ByteBooks/Adobe authorization")) end
                            local text = _("Account backup restored successfully.") .. NL .. NL .. table.concat(restored, NL)
                            if result.libby then
                                local refreshed, refresh_err = self.controller:refresh_libby_snapshot()
                                if refreshed then
                                    text = text .. NL .. NL .. _("Libby library refreshed successfully.")
                                    if self.catalog_browser and UIManager:isWidgetShown(self.catalog_browser) then
                                        self.catalog_browser:refreshSnapshot(refreshed, "live")
                                    end
                                else
                                    text = text .. NL .. NL .. _("Authentication was restored, but the Libby library refresh failed:") .. NL .. tostring(refresh_err)
                                end
                            end
                            UIManager:show(InfoMessage:new{ text = text })
                        else
                            UIManager:show(InfoMessage:new{ text = _("Could not restore account backup:") .. NL .. NL .. tostring(err) })
                        end
                    else
                        local path, metadata_or_err = self.controller:export_account_backup(label, password)
                        local text = path and (_("Encrypted account backup created:") .. NL .. NL .. tostring(label) .. NL .. tostring(path) .. NL .. NL
                            .. _("Keep both this file and its password safe. For reinstall or device-loss recovery, copy the backup somewhere outside this device."))
                            or (_("Could not export account backup:") .. NL .. NL .. tostring(metadata_or_err))
                        UIManager:show(InfoMessage:new{ text = text })
                    end
                    password = nil
                end },
            } },
        }
        UIManager:show(password_dialog)
        password_dialog:onShowKeyboard()
    end

    local function chooseImportBackup()
        local backups = self.controller:find_account_backups()
        if #backups == 0 then
            UIManager:show(InfoMessage:new{ text = _("No encrypted account backup was found in the standard backup locations.") })
            return
        end
        if #backups == 1 then
            passwordDialog(true, backups[1])
            return
        end
        local chooser_dialog
        local buttons = {}
        for _, backup in ipairs(backups) do
            local selected = backup
            table.insert(buttons, { { text = backupDisplayText(selected), callback = function()
                UIManager:close(chooser_dialog)
                passwordDialog(true, selected)
            end } })
        end
        table.insert(buttons, { { text = _("Cancel"), callback = function() UIManager:close(chooser_dialog) end } })
        chooser_dialog = TopAlignedButtonDialog:new{ title = _("Choose Account Backup"), buttons = buttons }
        UIManager:show(chooser_dialog)
    end

    dialog = ButtonDialog:new{
        title = _("Account Backup & Restore"),
        buttons = {
            { { text = _("Export encrypted backup"), callback = function() passwordDialog(false) end } },
            { { text = _("Import account backup"), callback = function() chooseImportBackup() end } },
            { { text = _("Back"), callback = function() UIManager:close(dialog); self:showAuthenticationSettings() end } },
        },
    }
    UIManager:show(dialog)
end

function LibbyDashboard:showLibbySettings()
    local dialog
    local authenticated = self.controller:libby_authenticated()
    dialog = ButtonDialog:new{
        title = _("Libby Setup") .. "\n" .. (authenticated and _("Status: authenticated") or _("Status: not authenticated")),
        buttons = {
            { { text = authenticated and _("Re-Login/Authenticate") or _("Login/Authenticate"), callback = function()
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
            { { text = _("Back"), callback = function() UIManager:close(dialog); self:showAuthenticationSettings() end } },
        },
    }
    UIManager:show(dialog)
end

function LibbyDashboard:showByteBooksLogin()
    self:runNetworkAction(function()
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
                            self:runNetworkAction(function()
                                local signing_in_message = InfoMessage:new{ text = _("Signing in to ByteBooks...") }
                            UIManager:show(signing_in_message)
                            UIManager:forceRePaint()
                            local registered, err = self.controller:create_adobe_account_registration(email, password, named_method)
                            password = nil
                            UIManager:close(signing_in_message)
                            UIManager:forceRePaint()
                            UIManager:show(InfoMessage:new{
                                text = registered
                                    and (_("ByteBooks authorization created successfully.")
                                        .. "\n\n" .. _("Account:") .. " " .. tostring(registered.username or email)
                                        .. "\n" .. _("ADEPT user:") .. " " .. tostring(registered.user or "")
                                        .. "\n\n" .. _("Create an Account Backup now so this authorization can be restored without registering another device."))
                                    or (_("ByteBooks sign-in failed:") .. "\n\n" .. tostring(err)),
                                })
                            end)
                        end,
                    },
                },
            },
        }
        UIManager:show(dialog)
        dialog:onShowKeyboard()
    end)
end

function LibbyDashboard:showAdobeSettings()
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
        title = _("ByteBooks / Adobe Authorization") .. "\n" .. status_text,
        buttons = {
            { { text = _("Register device (anonymous)"), callback = function()
                UIManager:close(dialog)
                self:runNetworkAction(function()
                    local registered, err = self.controller:create_adobe_registration()
                    UIManager:show(InfoMessage:new{
                        text = registered and _("Anonymous Adobe registration created successfully.")
                            or (_("Could not create Adobe registration:") .. string.char(10, 10) .. tostring(err)),
                    })
                end)
            end } },
            { { text = _("Sign in with ByteBooks account"), callback = function()
                UIManager:close(dialog)
                self:showByteBooksLogin()
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
            { { text = _("Back"), callback = function() UIManager:close(dialog); self:showAuthenticationSettings() end } },
        },
    }
    UIManager:show(dialog)
end

function LibbyDashboard:showShelfLayoutSettings(original_columns, original_rows, columns, rows)
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

function LibbyDashboard:showCleanupDiagnosticPrompt()
    local dialog
    dialog = MultiInputDialog:new{
        title = _("Diagnostics"),
        description = _("Enter diagnostic code."),
        fields = { { text = "", hint = _("Code") } },
        buttons = {
            {
                { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
                { text = _("Apply"), is_enter_default = true, callback = function()
                    local fields = dialog:getFields()
                    local code = koUtil.trim((fields and fields[1]) or "")
                    local code_hash = sha2.sha256(code)
                    local enabled
                    if code_hash == DEV_MODE_ON_SHA256 then
                        enabled = true
                    elseif code_hash == DEV_MODE_OFF_SHA256 then
                        enabled = false
                    else
                        UIManager:close(dialog)
                        return
                    end
                    self.controller.settings.developer_mode = enabled
                    self.controller.settings.cleanup_mode = enabled and "dry_run" or "normal"
                    self.controller:save()
                    if self.catalog_browser then
                        self.catalog_browser.return_enabled = not enabled
                        self.catalog_browser:updateItems()
                    end
                    UIManager:close(dialog)
                    UIManager:show(InfoMessage:new{
                        text = (enabled
                            and _("Developer mode enabled. New EPUB downloads will be saved decrypted, and loan cleanup will run in dry-run mode.")
                            or _("Developer mode disabled. New EPUB downloads will remain DRM-protected, and normal loan cleanup is active."))
                            .. _("\n\nRestart Libby Dashboard to reload the Main UI."),
                    })
                end },
            },
        },
    }
    UIManager:show(dialog)
end

function LibbyDashboard:showCredits()
    -- Long-pressing the final word "above" reveals the hidden developer entry point.
    local credits = [[
# Libby Dashboard for KOReader

A Libby library companion built for KOReader, bringing borrowed EPUB and PDF titles from your linked libraries into a reader-first interface.

## With appreciation

This project stands on ideas, research, and selected implementation patterns from several excellent open-source projects:

- [Bookshelf for KOReader](https://github.com/AndyHazz/bookshelf.koplugin) — inspiration and selected UI/layout patterns for the shelf, cover grid, hero area, and pagination.
- [Libby calibre plugin — sgmoore fork](https://github.com/sgmoore/libby-calibre-plugin) — selected Libby integration functions and protocol guidance.
- [Original Libby calibre plugin by ping](https://github.com/ping/libby-calibre-plugin) — the upstream project on which the sgmoore fork is based and an important source of Libby protocol research.
- [ACSM plugin for KOReader](https://github.com/kaikozlov/acsm.koplugin) — selected Adobe/ACSM implementation ideas that helped make fulfillment possible directly on KOReader devices.
- [KOReader](https://github.com/koreader/koreader) — the reader, plugin platform, widgets, and APIs that make all of this possible.

Many thanks to their authors and contributors for making their work available to the community.

## Links & Support

- [Techy Notes](https://techy-notes.com) — blog, projects, notes, and guides.
- [Jadehawk on YouTube](https://youtube.com/@jadehawk) — some projects tutorials.
- [Buy Me a Coffee](https://buymeacoffee.com/jadehawk) — if you would like to support my projects.

Libby Dashboard for KOReader is an independent personal project and is not affiliated with Libby, OverDrive, Adobe, Bytebooks or the projects credited above.
]]
    local viewer
    viewer = TextViewer:new{
        title = _("Credits"),
        text = credits,
        text_format = "md",
        justified = false,
        add_default_buttons = true,
        text_selection_callback = function(text)
            if koUtil.trim(text or ""):lower():gsub("[%p]+$", "") == "above" then
                UIManager:close(viewer)
                self:showCleanupDiagnosticPrompt()
            end
        end,
    }
    if viewer.box_widget then
        local box_widget = viewer.box_widget
        box_widget.html_link_tapped_callback = function(link)
            local uri = link and (link.uri or link.link or link.href)
            if type(uri) ~= "string" or not uri:match("^https?://") then return end
            if type(Device.canOpenLink) == "function" and Device:canOpenLink() then
                Device:openLink(uri)
            else
                UIManager:show(InfoMessage:new{
                    text = _("Open this link on another device:") .. "\n\n" .. uri,
                })
            end
        end
        -- Resolve Credits links directly so the hidden heading target works even
        -- when KOReader's global tap-to-follow-links preference is disabled.
        box_widget.onTapText = function(widget, _arg, ges)
            local pos = widget:getPosFromAbsPos(ges.pos)
            if not pos then return end
            local link = widget:getLinkByPosition(pos)
            if link then
                widget.html_link_tapped_callback(link)
                return true
            end
        end
    end
    UIManager:show(viewer)
end

function LibbyDashboard:showSettings()
    DiagnosticLog.log("[ui] settings:open")
    local dialog
    local buttons = {
        { { text = _("Authentication"), callback = function() UIManager:close(dialog); self:showAuthenticationSettings() end } },
        { { text = _("Shelf size"), callback = function() UIManager:close(dialog); self:showShelfLayoutSettings() end } },
    }
    if self.controller.settings.cleanup_mode == "dry_run" then
        table.insert(buttons, { { text = _("Book Storage"), callback = function() UIManager:close(dialog); self:showBookStorageSettings() end } })
    end
    table.insert(buttons, { { text = "──────────────", enabled = false } })
    table.insert(buttons, { { text = _("Check for Updates"), callback = function()
        require("libby_dashboard_updater").check(self, true)
    end } })
    table.insert(buttons, { { text = _("Credits"), callback = function() UIManager:close(dialog); self:showCredits() end } })
    table.insert(buttons, { { text = _("Close"), callback = function() UIManager:close(dialog) end } })
    dialog = ButtonDialog:new{
        title = _("Libby Dashboard") .. " (v" .. PLUGIN_VERSION .. ")",
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(dialog)
end

function LibbyDashboard:addToMainMenu(menu_items)
    local settings_items = {
        { text = _("Authentication"), callback = function() self:showAuthenticationSettings() end },
        { text = _("Shelf size"), callback = function() self:showShelfLayoutSettings() end },
    }
    if self.controller.settings.cleanup_mode == "dry_run" then
        table.insert(settings_items, { text = _("Book Storage"), callback = function() self:showBookStorageSettings() end })
    end
    table.insert(settings_items, { text = _("Credits"), callback = function() self:showCredits() end })
    menu_items.libby = {
        text = _("Libby Dashboard"),
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
                sub_item_table = settings_items,
            },
        },
    }
end

return LibbyDashboard
