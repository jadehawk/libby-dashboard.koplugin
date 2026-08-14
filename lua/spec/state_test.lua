package.path = "lua/?.lua;" .. package.path
package.preload["datastorage"] = package.preload["datastorage"] or function()
    return { getSettingsDir = function() return "/tmp" end }
end
package.preload["luasettings"] = package.preload["luasettings"] or function()
    return { open = function() return {} end }
end
package.preload["rapidjson"] = package.preload["rapidjson"] or function()
    return { encode = function() return "{}" end, decode = function() return {} end }
end

local AdobeProfile = require("adobe_profile")
local LibbyState = require("libby_state")
local KOReaderController = require("koreader_controller")
local KOReaderStorage = require("koreader_storage")
local KOReaderTransport = require("koreader_transport")
local LoanModel = require("loan_model")
local PathTemplate = require("path_template")

local function expect_equal(actual, expected, message)
    assert(actual == expected, (message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function test_libby_reset()
    local state = {
        libby_identity = "identity",
        pending_identity = "pending",
        pending_setup_code = "12345678",
        pending_blessing = "blessing",
    }

    assert(LibbyState.is_authenticated(state))
    assert(LibbyState.reset_credentials(state))
    assert(not LibbyState.is_authenticated(state))
    assert(state.pending_identity == nil)
    assert(state.pending_setup_code == nil)
    assert(state.pending_blessing == nil)
end

local function test_days_remaining()
    local now = 1000
    expect_equal(LibbyState.days_remaining(now + 1, now), 1)
    expect_equal(LibbyState.days_remaining(now + (2 * 86400), now), 2)
    expect_equal(LibbyState.days_remaining(now - 1, now), 0)
end

local function test_adobe_format_selection()
    local loan = {
        formats = {
            { id = "ebook-pdf-adobe" },
            { id = "ebook-epub-adobe" },
        },
    }
    expect_equal(LibbyState.preferred_adobe_format(loan), "ebook-epub-adobe")
end

local function test_loan_model()
    local loan = {
        id = "loan-1",
        cardId = "card-1",
        title = "Example Book",
        firstCreatorName = "Example Author",
        firstCreatorSortName = "Author, Example",
        detailedSeries = { seriesName = "Example Series", readingOrder = "2" },
        expireDate = 1000 + (3 * 86400),
        formats = {
            { id = "ebook-epub-adobe" },
        },
        covers = {
            cover300Wide = { href = "https://example.invalid/cover.jpg" },
        },
    }
    local cards = {
        {
            id = "card-1",
            advantageKey = "raw-key",
            library = { name = "Example Library" },
        },
    }

    local model = LoanModel.from_loan(loan, cards)
    expect_equal(model.title, "Example Book")
    expect_equal(model.author, "Example Author")
    expect_equal(model.series, "Example Series")
    expect_equal(model.series_index, "2")
    expect_equal(PathTemplate.author_firstname(model), "Example")
    expect_equal(PathTemplate.author_lastname(model), "Author")
    expect_equal(model.library, "Example Library")
    expect_equal(model.expires_at, loan.expireDate)
    expect_equal(model.adobe_format, "ebook-epub-adobe")
    expect_equal(model.media_type, "ebook")
    expect_equal(model.cover_url, "https://example.invalid/cover.jpg")
    expect_equal(LoanModel.media_type({ type = { id = "audiobook" } }), "audiobook")
    expect_equal(LoanModel.media_type({ type = { id = "magazine" } }), "magazine")
    expect_equal(
        LoanModel.library_name({ cardId = "42" }, { { id = 42, libraryName = "Numeric Card Library" } }),
        "Numeric Card Library"
    )
end

local function test_path_template()
    local model = {
        title = "Good Omens",
        author = "Terry Pratchett",
        authors = {
            { name = "Terry Pratchett", firstName = "Terry", lastName = "Pratchett" },
            { name = "Neil Gaiman", firstName = "Neil", lastName = "Gaiman" },
        },
        series = "Example Series",
        series_index = "3",
        library = "Example Library",
    }
    expect_equal(PathTemplate.first_author(model), "Terry Pratchett")
    expect_equal(PathTemplate.author_firstname(model), "Terry")
    expect_equal(PathTemplate.author_lastname(model), "Pratchett")
    expect_equal(PathTemplate.all_authors(model), "Terry Pratchett, Neil Gaiman")
    expect_equal(
        PathTemplate.resolve(PathTemplate.DEFAULT_TEMPLATE, model, { home = "/Books", ext = "epub" }),
        "/Books/Libby Books/Terry Pratchett/Example Series/Good Omens.epub"
    )
    expect_equal(
        PathTemplate.resolve(
            "{home}/{author}/{author:first}/{author:firstname}/{author:lastname}/{title}/{series}/{series_index}/{library}.{ext}",
            model,
            { home = "/Books", ext = "epub" }
        ),
        "/Books/Terry Pratchett, Neil Gaiman/Terry Pratchett/Terry/Pratchett/Good Omens/Example Series/3/Example Library.epub"
    )
    assert(PathTemplate.validate(PathTemplate.DEFAULT_TEMPLATE))
    local valid, err = PathTemplate.validate("{home}/{autor:first}/{title}.{ext}")
    assert(not valid)
    assert(err:find("autor:first", 1, true))
end

local function test_koreader_storage()
    local settings = {
        readSetting = function(_, key)
            if key == "home_dir" then return "/mnt/onboard/Books" end
        end,
    }
    local device = { home_dir = "/mnt/onboard" }
    expect_equal(KOReaderStorage.home_dir(settings, device, "/fallback"), "/mnt/onboard/Books")
    expect_equal(KOReaderStorage.home_dir({}, device, "/fallback"), "/mnt/onboard")
    expect_equal(KOReaderStorage.home_dir({}, {}, "/fallback"), "/fallback")

    local model = {
        title = "Good Omens",
        author = "Terry Pratchett",
        authors = { { name = "Terry Pratchett" }, { name = "Neil Gaiman" } },
    }
    expect_equal(
        KOReaderStorage.destination(PathTemplate.DEFAULT_TEMPLATE, model, {
            reader_settings = settings,
            device = device,
            cwd = "/fallback",
            ext = "epub",
        }),
        "/mnt/onboard/Books/Libby Books/Terry Pratchett/No Series/Good Omens.epub"
    )
end

local function test_koreader_controller()
    local saved = {
        libby_dashboard = {
            settings_version = 1,
            book_path_template = "{home}/{author:lastname}/{title}.{ext}",
            libby_identity = "identity",
            pending_libby_identity = "pending-identity",
            pending_libby_code = "12345678",
            pending_libby_generated_at = os.time() - 5,
        },
        home_dir = "/mnt/onboard/Books",
    }
    local flushed = false
    local store = {
        readSetting = function(_, key, default)
            local value = saved[key]
            if value == nil then return default end
            return value
        end,
        saveSetting = function(_, key, value) saved[key] = value end,
        flush = function() flushed = true end,
    }
    local controller = KOReaderController.new({ reader_settings = store, device = { home_dir = "/mnt/onboard" } })
    controller:load()
    assert(controller:libby_authenticated())
    expect_equal(controller.settings.libby_shelf_columns, 4)
    expect_equal(controller.settings.libby_shelf_rows, 2)
    expect_equal(controller.settings.libby_shelf_page, 1)
    local pending = controller:pending_libby_setup()
    expect_equal(pending.code, "12345678")
    assert(pending.remaining >= 54 and pending.remaining <= 55)
    expect_equal(controller:book_destination({ title = "Book", author = "Jane Doe", authors = { { name = "Jane Doe", sortName = "Doe, Jane" } } }, "epub"), "/mnt/onboard/Books/Doe/Book.epub")
    assert(controller:set_book_path_template(PathTemplate.DEFAULT_TEMPLATE))
    assert(flushed)
    expect_equal(saved.libby_dashboard.book_path_template, PathTemplate.DEFAULT_TEMPLATE)

    controller.sync_libby = function()
        return {
            cards = { { id = "card-1", libraryName = "Test Library" } },
            loans = { {
                id = "loan-1",
                cardId = "card-1",
                title = "Cached Book",
                firstCreatorName = "Jane Doe",
                firstCreatorSortName = "Doe, Jane",
                creators = { { name = "Jane Doe", firstName = "Jane", lastName = "Doe", sortName = "Doe, Jane" } },
                detailedSeries = { seriesName = "Test Series", readingOrder = "4" },
                formats = { { id = "ebook-epub-adobe" } },
            } },
        }
    end
    local snapshot = assert(controller:refresh_libby_snapshot())
    expect_equal(snapshot.cards[1].name, "Test Library")
    expect_equal(snapshot.loans[1].title, "Cached Book")
    expect_equal(snapshot.loans[1].library, "Test Library")
    expect_equal(snapshot.loans[1].series, "Test Series")
    expect_equal(snapshot.loans[1].series_index, "4")
    expect_equal(snapshot.loans[1].media_type, "ebook")
    assert(snapshot.loans[1].raw == nil)
    assert(controller:set_book_path_template(
        "{home}/{library}/{author:first}/{author:firstname}/{author:lastname}/{series}/{series_index}/{title}.{ext}"
    ))
    expect_equal(
        controller:book_destination(snapshot.loans[1], "epub"),
        "/mnt/onboard/Books/Test Library/Jane Doe/Jane/Doe/Test Series/4/Cached Book.epub"
    )
    expect_equal(controller:cached_libby_snapshot(), snapshot)
    expect_equal(saved.libby_dashboard.libby_snapshot, snapshot)

    local future = os.time() + 3600
    assert(controller:track_downloaded_loan({
        id = "loan-1", card_id = "card-1", title = "Cached Book",
        author = "Jane Doe", library = "Test Library", expires_at = future,
    }, "/books/cached.epub"))
    expect_equal(controller:downloaded_loan("loan-1").path, "/books/cached.epub")
    expect_equal(controller:downloaded_loan("loan-1").expires_at, future)

    local removed_path
    controller.settings.cleanup_mode = "dry_run"
    local ok, removed, candidates = controller:reconcile_downloaded_loans({ loans = {} }, function(path)
        removed_path = path
    end)
    assert(ok)
    expect_equal(removed, 0)
    expect_equal(candidates, 1)
    assert(removed_path == nil)
    assert(controller:downloaded_loan("loan-1") ~= nil)

    controller.settings.cleanup_mode = "normal"
    ok, removed, candidates = controller:reconcile_downloaded_loans({ loans = {} }, function(path)
        removed_path = path
    end)
    assert(ok)
    expect_equal(removed, 1)
    expect_equal(candidates, 1)
    expect_equal(removed_path, "/books/cached.epub")
    assert(controller:downloaded_loan("loan-1") == nil)
end

local function test_koreader_transport()
    local captured
    local timeout_set = false
    local timeout_reset = false
    local transport = KOReaderTransport.new({
        https = {
            request = function(spec)
                captured = spec
                spec.sink('{"ok":true}')
                spec.sink(nil)
                return 1, 200, { ["content-type"] = "application/json" }, "HTTP/1.1 200 OK"
            end,
        },
        ltn12 = {
            source = { string = function(value) return function() return value end end },
            sink = { table = function(parts)
                return function(chunk)
                    if chunk then table.insert(parts, chunk) end
                    return 1
                end
            end },
        },
        json_encode = function() return "{}" end,
        json_decode = function() return { ok = true } end,
        socketutil = {
            LARGE_BLOCK_TIMEOUT = 10,
            LARGE_TOTAL_TIMEOUT = 20,
            set_timeout = function() timeout_set = true end,
            reset_timeout = function() timeout_reset = true end,
        },
    })

    local response, err = transport:request({
        method = "GET",
        base_url = "https://example.invalid",
        path = "/chip",
        query = { z = "a b", a = "1" },
        headers = { Accept = "application/json" },
    })
    assert(response, err)
    expect_equal(response.status, 200)
    assert(response.body.ok)
    expect_equal(captured.url, "https://example.invalid/chip?a=1&z=a%20b")
    expect_equal(captured.headers["Accept-Encoding"], "identity")
    assert(captured.redirect == false)
    assert(timeout_set and timeout_reset)
end

local function valid_profile()
    return {
        deviceKey = "device-key",
        privateLicenseKey = "private-key",
        licenseCert = "license-cert",
        user = "urn:uuid:user",
        username = "anonymous",
        pkcs12 = "pkcs12-data",
        deviceUUID = "device-uuid",
        fingerprint = "fingerprint",
        authCert = "auth-cert",
        activationURL = "https://example.invalid/adept",
    }
end

local function test_adobe_profile_round_trip()
    local profile, err = AdobeProfile.from_activation_blob(valid_profile())
    assert(profile, err)
    expect_equal(profile.profileVersion, 1)
    expect_equal(profile.deviceUUID, "device-uuid")

    local blob, blob_err = AdobeProfile.to_activation_blob(profile)
    assert(blob, blob_err)
    expect_equal(blob.privateLicenseKey, "private-key")

    local summary = AdobeProfile.summary(blob)
    assert(summary.registered)
    expect_equal(summary.deviceUUID, "device-uuid")
    expect_equal(summary.authorizationType, "anonymous")

    blob.username = "reader@example.com"
    summary = AdobeProfile.summary(blob)
    expect_equal(summary.authorizationType, "account")
end

local function test_libby_adobe_authorization_precedence()
    local account = valid_profile()
    account.authorizationType = "account"
    account.username = "reader@example.com"
    assert(not AdobeProfile.should_adopt_external(account), "ByteBooks account authorization must remain authoritative")

    local anonymous = valid_profile()
    anonymous.authorizationType = "anonymous"
    anonymous.username = "anonymous"
    assert(not AdobeProfile.should_adopt_external(anonymous), "Libby anonymous authorization must remain authoritative")

    assert(AdobeProfile.should_adopt_external(nil), "acsm.lua may bootstrap when Libby has no authorization")
    local invalid = valid_profile()
    invalid.pkcs12 = nil
    assert(AdobeProfile.should_adopt_external(invalid), "acsm.lua may bootstrap when Libby's saved authorization is invalid")
end

local function test_adobe_profile_validation()
    local invalid = valid_profile()
    invalid.pkcs12 = nil
    local ok, err = AdobeProfile.validate(invalid)
    assert(not ok)
    assert(err:find("pkcs12", 1, true))
end

local function test_adobe_reset()
    local state = {
        adobe_registration = valid_profile(),
    }
    assert(AdobeProfile.reset(state))
    assert(state.adobe_registration == nil)
end

local tests = {
    test_libby_reset,
    test_days_remaining,
    test_adobe_format_selection,
    test_loan_model,
    test_path_template,
    test_koreader_storage,
    test_koreader_controller,
    test_koreader_transport,
    test_adobe_profile_round_trip,
    test_libby_adobe_authorization_precedence,
    test_adobe_profile_validation,
    test_adobe_reset,
}

for _, test in ipairs(tests) do
    test()
end

print("Lua state tests passed (" .. tostring(#tests) .. ")")
