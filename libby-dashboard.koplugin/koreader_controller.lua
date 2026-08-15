local AdobeProfile = require("adobe_profile")
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local rapidjson = require("rapidjson")
local KOReaderStorage = require("koreader_storage")
local KOReaderTransport = require("koreader_transport")
local LibbyClient = require("libby_client")
local LibbyState = require("libby_state")
local LoanModel = require("loan_model")
local PathTemplate = require("path_template")

local KOReaderController = {}
KOReaderController.__index = KOReaderController

KOReaderController.SETTINGS_KEY = "libby_dashboard"

local DEFAULTS = {
    settings_version = 1,
    book_path_template = PathTemplate.DEFAULT_TEMPLATE,
    libby_shelf_columns = 4,
    libby_shelf_rows = 2,
    libby_shelf_page = 1,
    libby_snapshot = nil,
    libby_identity = nil,
    downloaded_loans = {},
    cleanup_mode = "normal",
    adobe_registration = nil,
}

local function copy_defaults()
    local result = {}
    for key, value in pairs(DEFAULTS) do result[key] = value end
    return result
end

function KOReaderController.new(options)
    options = options or {}
    return setmetatable({
        reader_settings = options.reader_settings,
        settings_store = options.settings_store or options.reader_settings,
        device = options.device,
        cwd = options.cwd,
        transport = options.transport,
        settings = copy_defaults(),
    }, KOReaderController)
end

function KOReaderController:load()
    local store = self.settings_store
    local loaded
    if type(store) == "table" and type(store.readSetting) == "function" then
        local ok, value = pcall(store.readSetting, store, KOReaderController.SETTINGS_KEY, nil)
        if ok and type(value) == "table" then loaded = value end
    end

    -- One-time migration from the old G_reader_settings entry into the
    -- dedicated settings/libby-dashboard.lua store. Keep G_reader_settings only for
    -- KOReader-owned globals such as home_dir.
    if loaded == nil and store ~= self.reader_settings then
        local legacy = self.reader_settings
        if type(legacy) == "table" and type(legacy.readSetting) == "function" then
            local ok, value = pcall(legacy.readSetting, legacy, KOReaderController.SETTINGS_KEY, nil)
            if ok and type(value) == "table" then
                loaded = value
                store:saveSetting(KOReaderController.SETTINGS_KEY, value)
                if type(store.flush) == "function" then store:flush() end
                if type(legacy.delSetting) == "function" then
                    legacy:delSetting(KOReaderController.SETTINGS_KEY)
                    if type(legacy.flush) == "function" then legacy:flush() end
                end
            end
        end
    end

    self.settings = copy_defaults()
    for key, value in pairs(loaded or {}) do self.settings[key] = value end
    if self.settings.book_path_template == PathTemplate.LEGACY_DEFAULT_TEMPLATE
            or not PathTemplate.validate(self.settings.book_path_template) then
        self.settings.book_path_template = PathTemplate.DEFAULT_TEMPLATE
    end
    -- Libby's saved authorization is authoritative once it exists, whether it
    -- is a ByteBooks account or an anonymous ADEPT identity. acsm.lua is only
    -- a first-run bootstrap source and must never replace a valid Libby profile.
    if AdobeProfile.should_adopt_external(self.settings.adobe_registration) then
        self:adopt_acsm_registration()
    end
    return self.settings
end

function KOReaderController:save()
    local store = self.settings_store
    if type(store) ~= "table" or type(store.saveSetting) ~= "function" then
        return nil, "KOReader settings store is unavailable"
    end
    store:saveSetting(KOReaderController.SETTINGS_KEY, self.settings)
    if type(store.flush) == "function" then store:flush() end
    return true
end

function KOReaderController:set_book_path_template(template)
    local valid, err = PathTemplate.validate(template)
    if not valid then return nil, err end
    self.settings.book_path_template = template
    return self:save()
end

function KOReaderController:reset_book_path_template()
    self.settings.book_path_template = PathTemplate.DEFAULT_TEMPLATE
    return self:save()
end

function KOReaderController:book_destination(model, ext)
    return KOReaderStorage.destination(self.settings.book_path_template, model, {
        reader_settings = self.reader_settings,
        device = self.device,
        cwd = self.cwd,
        ext = ext,
    })
end

function KOReaderController:libby_client()
    local transport = self.transport or KOReaderTransport.new()
    self.transport = transport
    local loaded, load_err = transport:_load()
    if not loaded then return nil, load_err end

    return LibbyClient.new({
        transport = transport,
        identity = self.settings.libby_identity,
        json_decode = transport.json_decode,
        on_identity = function(identity)
            self.settings.libby_identity = identity
            self:save()
        end,
    })
end

function KOReaderController:test_libby_connection()
    local client, client_err = self:libby_client()
    if not client then return nil, client_err end
    local chip, chip_err = client:get_chip(false, false)
    if not chip then return nil, chip_err end
    return true
end

function KOReaderController:sync_libby()
    if not self:libby_authenticated() then
        return nil, "Libby is not authenticated"
    end
    local client, client_err = self:libby_client()
    if not client then return nil, client_err end
    return client:sync()
end

function KOReaderController:download_loan_acsm(loan)
    if type(loan) ~= "table" then return nil, "Loan is missing" end
    if not loan.adobe_format then return nil, "This loan has no Adobe EPUB/PDF format" end
    local client, client_err = self:libby_client()
    if not client then return nil, client_err end
    return client:fulfill_adobe_loan(loan.card_id, loan.id, loan.adobe_format)
end

function KOReaderController:cached_libby_snapshot()
    local snapshot = self.settings.libby_snapshot
    if type(snapshot) ~= "table" then return nil end
    return snapshot
end

function KOReaderController:normalize_libby_state(state)
    if type(state) ~= "table" then return nil, "Libby sync state is invalid" end

    local cards = {}
    for _, card in ipairs(state.cards or {}) do
        table.insert(cards, {
            id = card.id or card.cardId,
            name = LoanModel.card_name(card),
        })
    end

    local loans = {}
    for _, loan in ipairs(LoanModel.list(state.loans or {}, state.cards or {})) do
        table.insert(loans, {
            id = loan.id,
            card_id = loan.card_id,
            title = loan.title,
            author = loan.author,
            authors = loan.authors,
            series = loan.series,
            series_index = loan.series_index,
            library = loan.library,
            days_remaining = loan.days_remaining,
            expires_at = loan.expires_at,
            adobe_format = loan.adobe_format,
            media_type = loan.media_type,
            cover_url = loan.cover_url,
        })
    end

    return {
        updated_at = os.time(),
        cards = cards,
        loans = loans,
    }
end

function KOReaderController:save_libby_snapshot(snapshot)
    if type(snapshot) ~= "table" then return nil, "Libby snapshot is invalid" end
    self.settings.libby_snapshot = snapshot
    return self:save()
end

function KOReaderController:track_downloaded_loan(loan, path)
    if type(loan) ~= "table" or loan.id == nil then return nil, "Loan id is missing" end
    if type(path) ~= "string" or path == "" then return nil, "Downloaded book path is missing" end
    if type(self.settings.downloaded_loans) ~= "table" then self.settings.downloaded_loans = {} end
    self.settings.downloaded_loans[tostring(loan.id)] = {
        loan_id = loan.id,
        card_id = loan.card_id,
        title = loan.title,
        author = loan.author,
        library = loan.library,
        path = path,
        format = path:match("%.([^./]+)$"),
        downloaded_at = os.time(),
        expires_at = loan.expires_at,
    }
    return self:save()
end

function KOReaderController:downloaded_loan(loan_id)
    local records = self.settings.downloaded_loans
    if type(records) ~= "table" or loan_id == nil then return nil end
    return records[tostring(loan_id)]
end

function KOReaderController:reconcile_downloaded_loans(snapshot, remove_book)
    local records = self.settings.downloaded_loans
    if type(records) ~= "table" then
        self.settings.downloaded_loans = {}
        return true, 0, 0
    end
    local active = {}
    for _, loan in ipairs(type(snapshot) == "table" and snapshot.loans or {}) do
        if loan.id ~= nil then active[tostring(loan.id)] = true end
    end
    local now = os.time()
    local removed = 0
    local candidates = 0
    local dry_run = self.settings.cleanup_mode == "dry_run"
    for key, record in pairs(records) do
        local expired = type(record.expires_at) == "number" and record.expires_at <= now
        if expired or not active[key] then
            candidates = candidates + 1
            if not dry_run then
                local cleanup_ok = true
                if type(remove_book) == "function" and type(record.path) == "string" then
                    cleanup_ok = remove_book(record) ~= false
                end
                if cleanup_ok then
                    records[key] = nil
                    removed = removed + 1
                end
            end
        end
    end
    if removed > 0 then
        local saved, err = self:save()
        if not saved then return nil, err end
    end
    return true, removed, candidates
end

function KOReaderController:refresh_libby_snapshot()
    local state, err = self:sync_libby()
    if not state then return nil, err end
    local snapshot, normalize_err = self:normalize_libby_state(state)
    if not snapshot then return nil, normalize_err end
    local saved, save_err = self:save_libby_snapshot(snapshot)
    if not saved then return nil, save_err end
    return snapshot
end

function KOReaderController:begin_libby_setup()
    local transport = self.transport or KOReaderTransport.new()
    self.transport = transport
    local loaded, load_err = transport:_load()
    if not loaded then return nil, load_err end

    local client = LibbyClient.new({
        transport = transport,
        json_decode = transport.json_decode,
    })
    local setup, setup_err = client:begin_setup()
    if not setup then return nil, setup_err end

    self.settings.pending_libby_identity = client.identity
    self.settings.pending_libby_code = setup.code
    self.settings.pending_libby_generated_at = os.time()
    self:save()
    return setup
end

function KOReaderController:complete_libby_setup()
    local identity = self.settings.pending_libby_identity
    local code = self.settings.pending_libby_code
    if type(identity) ~= "string" or identity == "" or type(code) ~= "string" or code == "" then
        return nil, "No pending Libby setup code"
    end

    local transport = self.transport or KOReaderTransport.new()
    self.transport = transport
    local loaded, load_err = transport:_load()
    if not loaded then return nil, load_err end

    local final_identity
    local client = LibbyClient.new({
        transport = transport,
        identity = identity,
        json_decode = transport.json_decode,
        on_identity = function(value) final_identity = value end,
    })
    local sync_state, setup_err = client:complete_setup(code)
    if not sync_state then return nil, setup_err end

    self.settings.libby_identity = final_identity or client.identity
    self:clear_pending_libby_setup()
    self:save()
    return sync_state
end

function KOReaderController:clear_pending_libby_setup()
    self.settings.pending_libby_identity = nil
    self.settings.pending_libby_code = nil
    self.settings.pending_libby_generated_at = nil
end

function KOReaderController:pending_libby_setup()
    local generated_at = self.settings.pending_libby_generated_at
    local code = self.settings.pending_libby_code
    if type(generated_at) ~= "number" or type(code) ~= "string" then return nil end
    return {
        code = code,
        generated_at = generated_at,
        remaining = math.max(0, 60 - (os.time() - generated_at)),
    }
end

function KOReaderController:libby_authenticated()
    return LibbyState.is_authenticated(self.settings)
end

function KOReaderController:reset_libby_credentials()
    self.settings.libby_identity = nil
    self.settings.libby_snapshot = nil
    self:clear_pending_libby_setup()
    return self:save()
end

function KOReaderController:adobe_registered()
    return AdobeProfile.summary(self.settings.adobe_registration).registered == true
end

function KOReaderController:adopt_acsm_registration()
    if self:adobe_registered() then return AdobeProfile.summary(self.settings.adobe_registration), false end
    local settings_path = DataStorage:getSettingsDir() .. "/acsm.lua"
    local ok, settings = pcall(LuaSettings.open, LuaSettings, settings_path)
    if not ok or type(settings) ~= "table" or type(settings.readSetting) ~= "function" then return nil, false end
    local activation = settings:readSetting("activation")
    if type(activation) ~= "table" then return nil, false end
    local profile = AdobeProfile.from_activation_blob(activation)
    if not profile then return nil, false end
    self.settings.adobe_registration = profile
    local saved = self:save()
    if not saved then return nil, false end
    return AdobeProfile.summary(profile), true
end

local function save_adobe_credentials(controller, adobe, auth_info, creds, authorization_type, sign_in_method)
    local device_uuid, fingerprint_or_err = adobe.activate(creds.user, creds.deviceKey, creds.pkcs12)
    if not device_uuid then return nil, fingerprint_or_err end

    local serialized, serialize_err = adobe.serializeActivation(
        creds,
        device_uuid,
        fingerprint_or_err,
        auth_info.certificate,
        creds.activationURL
    )
    if not serialized then return nil, serialize_err end
    serialized.authorizationType = authorization_type
    serialized.signInMethod = sign_in_method

    local profile, profile_err = AdobeProfile.normalize(serialized)
    if not profile then return nil, profile_err end
    controller.settings.adobe_registration = profile
    local saved, save_err = controller:save()
    if not saved then return nil, save_err end
    return AdobeProfile.summary(profile)
end

function KOReaderController:adobe_sign_in_methods()
    local adobe = require("adobe.adobe")
    local auth_info, auth_err = adobe.getAuthenticationServiceInfo()
    if not auth_info then return nil, auth_err end
    return auth_info.methods or {}, auth_info
end

function KOReaderController:create_adobe_registration()
    local adobe = require("adobe.adobe")
    local auth_info, auth_err = adobe.getAuthenticationServiceInfo()
    if not auth_info then return nil, auth_err end

    local creds, sign_in_err = adobe.signIn("anonymous", "", "", auth_info.certificate)
    if not creds then return nil, sign_in_err end
    return save_adobe_credentials(self, adobe, auth_info, creds, "anonymous", "anonymous")
end

function KOReaderController:create_adobe_account_registration(username, password, method)
    if type(username) ~= "string" or username == "" then return nil, "ByteBooks email is required" end
    if type(password) ~= "string" or password == "" then return nil, "ByteBooks password is required" end

    local adobe = require("adobe.adobe")
    local auth_info, auth_err = adobe.getAuthenticationServiceInfo()
    if not auth_info then return nil, auth_err end

    if not method then
        for _, candidate in ipairs(auth_info.methods or {}) do
            local candidate_method = candidate.method
            if type(candidate_method) == "string" and candidate_method ~= "" and candidate_method:lower() ~= "anonymous" then
                method = candidate_method
                break
            end
        end
    end
    if not method then return nil, "The Adobe authentication service did not advertise a named-account sign-in method" end

    local creds, sign_in_err = adobe.signIn(method, username, password, auth_info.certificate)
    password = nil
    if not creds then return nil, sign_in_err end
    return save_adobe_credentials(self, adobe, auth_info, creds, "account", method)
end

function KOReaderController:ensure_adobe_registration()
    if self:adobe_registered() then return AdobeProfile.summary(self.settings.adobe_registration), "libby-dashboard" end
    local adopted = self:adopt_acsm_registration()
    if adopted then return adopted, "acsm" end
    local created, err = self:create_adobe_registration()
    if not created then return nil, err end
    return created, "generated"
end

function KOReaderController:adobe_export_path()
    return KOReaderStorage.home_dir(self.reader_settings, self.device, self.cwd) .. "/libby-dashboard-adobe-bytebooks-auth.json"
end

function KOReaderController:export_adobe_registration()
    local profile, err = AdobeProfile.normalize(self.settings.adobe_registration)
    if not profile then return nil, err end
    local path = self:adobe_export_path()
    local file, file_err = io.open(path, "wb")
    if not file then return nil, file_err end
    local ok, encoded = pcall(rapidjson.encode, profile)
    if not ok or type(encoded) ~= "string" then file:close(); return nil, tostring(encoded or "Could not encode Adobe registration") end
    file:write(encoded)
    file:close()
    return path
end

function KOReaderController:import_adobe_registration(path)
    path = path or self:adobe_export_path()
    local file, file_err = io.open(path, "rb")
    if not file then return nil, file_err end
    local contents = file:read("*a")
    file:close()
    local ok, decoded = pcall(rapidjson.decode, contents)
    if not ok or type(decoded) ~= "table" then return nil, "Adobe authorization file is invalid" end
    local profile, profile_err = AdobeProfile.normalize(decoded)
    if not profile then return nil, profile_err end
    self.settings.adobe_registration = profile
    local saved, save_err = self:save()
    if not saved then return nil, save_err end
    return AdobeProfile.summary(profile)
end

function KOReaderController:reset_adobe_registration()
    AdobeProfile.reset(self.settings)
    return self:save()
end

function KOReaderController:adobe_summary()
    return AdobeProfile.summary(self.settings.adobe_registration)
end

function KOReaderController:fulfill_acsm(acsm_path, output_path)
    local profile, profile_err = AdobeProfile.normalize(self.settings.adobe_registration)
    if not profile then return nil, profile_err end

    local adobe = require("adobe.adobe")
    local fulfillment = require("adobe.fulfillment")
    local restored, restore_err = adobe.restoreActivation(profile)
    if not restored then return nil, restore_err end

    return fulfillment.process(
        acsm_path,
        output_path,
        restored.creds,
        restored.deviceUUID,
        restored.fingerprint,
        restored.authCert
    )
end

function KOReaderController:status()
    return {
        libby_authenticated = self:libby_authenticated(),
        adobe_registered = self:adobe_registered(),
        home_dir = KOReaderStorage.home_dir(self.reader_settings, self.device, self.cwd),
        book_path_template = self.settings.book_path_template,
    }
end

return KOReaderController
