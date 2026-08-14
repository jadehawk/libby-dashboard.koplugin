package.path = "lua/?.lua;" .. package.path

local cjson = require("cjson")
local AdobeProfile = require("adobe_profile")
local HttpTransport = require("http_transport")
local LibbyClient = require("libby_client")
local LibbyState = require("libby_state")
local LoanModel = require("loan_model")
local PathTemplate = require("path_template")
local StateStore = require("state_store")

local USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36 Edg/151.0.0.0"

local cwd = os.getenv("PWD") or "."
local state_dir = cwd .. "/.libby-cli"
local store = StateStore.new(state_dir .. "/state.json")
local state, load_err = store:load()
if not state then
    io.stderr:write("Could not load state: " .. tostring(load_err) .. "\n")
    os.exit(1)
end

local transport = HttpTransport.new()

local function save_state()
    local ok, err = store:save(state)
    if not ok then
        io.stderr:write("Could not save state: " .. tostring(err) .. "\n")
        return nil
    end
    return true
end

local function pause()
    io.write("\nPress Enter to continue...")
    io.read("*l")
end

local function prompt(text)
    io.write(text)
    return io.read("*l")
end

local function clear_screen()
    io.write("\27[2J\27[H")
    io.flush()
end

local function wait_for_enter_one_second()
    return os.execute([[bash -c 'read -r -t 1 _']]) == 0
end

local function authenticated_client()
    if not LibbyState.is_authenticated(state) then
        return nil, "Libby is not authenticated"
    end
    return LibbyClient.new({
        transport = transport,
        identity = state.libby_identity,
        json_decode = HttpTransport.json_decode,
        user_agent = USER_AGENT,
        on_identity = function(identity)
            state.libby_identity = identity
            save_state()
        end,
    })
end

local SETUP_CODE_TTL_SECONDS = 60

local function clear_pending_setup()
    state.pending_identity = nil
    state.pending_setup_code = nil
    state.pending_setup_expiry = nil
    state.pending_setup_generated_at = nil
end

local function setup_code_remaining()
    if type(state.pending_setup_generated_at) ~= "number" then
        return 0
    end
    local remaining = SETUP_CODE_TTL_SECONDS - (os.time() - state.pending_setup_generated_at)
    return math.max(0, remaining)
end

local function verify_current_setup_code()
    if type(state.pending_identity) ~= "string" or type(state.pending_setup_code) ~= "string" then
        return nil, "No pending setup code"
    end

    local final_identity
    local client = LibbyClient.new({
        transport = transport,
        identity = state.pending_identity,
        json_decode = HttpTransport.json_decode,
        user_agent = USER_AGENT,
        on_identity = function(identity)
            final_identity = identity
        end,
    })

    io.write("Verifying setup code...\n")
    local sync_state, err = client:complete_setup(state.pending_setup_code)
    if not sync_state then
        return nil, err
    end

    state.libby_identity = final_identity or client.identity
    clear_pending_setup()
    if not save_state() then
        return nil, "Could not save authenticated Libby state"
    end

    print("Libby authentication complete.")
    print("Library cards found: " .. tostring(#(sync_state.cards or {})))
    print("Current loans found: " .. tostring(#(sync_state.loans or {})))
    return true
end

local function generate_setup_code()
    print("\nLibby device setup")
    print("------------------")
    print("On an already signed-in Libby device, open:")
    print("Menu -> Copy To Another Device -> Enter Setup Code")
    print("")
    print("The setup code is valid for only 60 seconds after it is generated.")
    print("Have the signed-in Libby device ready on the Enter Setup Code screen before continuing.")

    local ready = prompt("\nGenerate a setup code now? [Y/n] ")
    if ready and ready ~= "" and ready:lower() ~= "y" then
        print("Cancelled.")
        return
    end

    while true do
        local client = LibbyClient.new({
            transport = transport,
            json_decode = HttpTransport.json_decode,
            user_agent = USER_AGENT,
        })

        io.write("Contacting Libby...\n")
        local result, err = client:begin_setup()
        if not result then
            print("Setup-code generation failed: " .. tostring(err))
            return
        end

        state.pending_identity = client.identity
        state.pending_setup_code = result.code
        state.pending_setup_expiry = result.expiry
        state.pending_setup_generated_at = os.time()
        if not save_state() then
            return
        end

        local last_verify_error
        while true do
            local remaining = setup_code_remaining()
            if remaining <= 0 then
                clear_pending_setup()
                save_state()
                clear_screen()
                print("Libby device setup")
                print("------------------")
                print("The 60-second setup code has expired.")
                local regenerate = prompt("\nGenerate a new setup code? [Y/n] ")
                if regenerate and regenerate ~= "" and regenerate:lower() ~= "y" then
                    return
                end
                break
            end

            clear_screen()
            print("Libby device setup")
            print("------------------")
            print("Enter this code on the signed-in Libby device:")
            print("")
            print("            " .. tostring(result.code))
            print("")
            print(string.format("Code expires in: %02d seconds", remaining))
            print("After Libby shows Done/OK, press Enter to verify.")
            if last_verify_error then
                print("Last verification: " .. tostring(last_verify_error))
            end

            if wait_for_enter_one_second() then
                local verified, verify_err = verify_current_setup_code()
                if verified then
                    return
                end
                last_verify_error = verify_err
            end
        end
    end
end

local function list_cards()
    local client, err = authenticated_client()
    if not client then
        print(err)
        return
    end

    local cards, cards_err = client:get_cards()
    if not cards then
        print("Could not load cards: " .. tostring(cards_err))
        return
    end
    if #cards == 0 then
        print("No library cards found.")
        return
    end

    print("\nLibrary cards")
    for index, card in ipairs(cards) do
        print(string.format("%2d. %s", index, LoanModel.card_name(card)))
    end
end

local function show_loan_details(loan)
    while true do
        clear_screen()
        print(loan.title)
        print(string.rep("-", math.min(#loan.title, 60)))
        if loan.author then
            print("Author: " .. tostring(loan.author))
        end
        if loan.library then
            print("Library: " .. tostring(loan.library))
        end
        if loan.series then
            local series_text = tostring(loan.series)
            if loan.series_index ~= nil then
                series_text = series_text .. " #" .. tostring(loan.series_index)
            end
            print("Series: " .. series_text)
        end
        if loan.days_remaining ~= nil then
            local days = loan.days_remaining
            print("Loan: " .. tostring(days) .. " day" .. (days == 1 and "" or "s") .. " remaining")
        end
        if loan.adobe_format then
            print("Format: " .. tostring(loan.adobe_format))
            local ext = loan.adobe_format == "ebook-pdf-adobe" and "pdf" or "epub"
            local destination = PathTemplate.resolve(
                state.book_path_template or PathTemplate.DEFAULT_TEMPLATE,
                loan,
                { home = ".", ext = ext }
            )
            print("Destination (CLI): " .. destination)
        else
            print("Format: no Adobe EPUB/PDF download")
        end
        print("Cover metadata: " .. (loan.cover_url and "available" or "not present"))
        print("")
        print("0. Back")
        local choice = prompt("\nChoice: ")
        if choice == "0" or choice == nil then
            return
        end
    end
end

local function list_loans()
    local client, err = authenticated_client()
    if not client then
        print(err)
        return
    end

    local sync_state, sync_err = client:sync()
    if not sync_state then
        print("Could not load loans: " .. tostring(sync_err))
        return
    end

    local models = LoanModel.list(sync_state.loans or {}, sync_state.cards or {})
    if #models == 0 then
        print("No current loans found.")
        return
    end

    while true do
        clear_screen()
        print("Current loans")
        print("-------------")
        for index, loan in ipairs(models) do
            print(string.format("%2d. %s", index, loan.title))
            if loan.author then
                print("    " .. tostring(loan.author))
            end
            if loan.days_remaining ~= nil then
                local days = loan.days_remaining
                print("    " .. tostring(days) .. " day" .. (days == 1 and "" or "s") .. " remaining")
            end
        end
        print("")
        print("0. Back")

        local choice = prompt("\nSelect a loan: ")
        if choice == "0" or choice == nil then
            return
        end

        local index = tonumber(choice)
        if index and models[index] then
            show_loan_details(models[index])
        else
            print("Unknown choice.")
            pause()
        end
    end
end

local function reset_libby()
    if not LibbyState.is_authenticated(state) and not state.pending_identity then
        print("No Libby credentials are stored.")
        return
    end
    local answer = prompt("Delete stored Libby credentials and pending setup state? [y/N] ")
    if answer and answer:lower() == "y" then
        LibbyState.reset_credentials(state)
        state.pending_setup_expiry = nil
        save_state()
        print("Libby credentials reset. Adobe registration was not changed.")
    else
        print("Cancelled.")
    end
end

local function adobe_status()
    local summary = AdobeProfile.summary(state.adobe_registration)
    if not summary.registered then
        print("Adobe registration: not set")
        return
    end
    print("Adobe registration: ready")
    print("Profile version: " .. tostring(summary.profileVersion))
    print("Device UUID: " .. tostring(summary.deviceUUID))
end

local function export_adobe()
    local profile, err = AdobeProfile.normalize(state.adobe_registration)
    if not profile then
        print("No valid Adobe registration to export: " .. tostring(err))
        return
    end
    local path = prompt("Export path [./adobe-registration.json]: ")
    if not path or path == "" then
        path = cwd .. "/adobe-registration.json"
    end
    local file, open_err = io.open(path, "wb")
    if not file then
        print("Could not export registration: " .. tostring(open_err))
        return
    end
    file:write(cjson.encode(profile), "\n")
    file:close()
    os.execute(string.format("chmod 600 %q >/dev/null 2>&1", path))
    print("Adobe registration exported. Treat this file as a private credential.")
end

local function import_adobe()
    local path = prompt("Adobe registration JSON path: ")
    if not path or path == "" then
        print("Cancelled.")
        return
    end
    local file, open_err = io.open(path, "rb")
    if not file then
        print("Could not open registration: " .. tostring(open_err))
        return
    end
    local raw = file:read("*a")
    file:close()
    local ok, decoded = pcall(cjson.decode, raw)
    if not ok then
        print("Registration file is not valid JSON.")
        return
    end
    local profile, profile_err = AdobeProfile.normalize(decoded)
    if not profile then
        print("Registration file is invalid: " .. tostring(profile_err))
        return
    end
    state.adobe_registration = profile
    save_state()
    print("Adobe registration imported.")
end

local function reset_adobe()
    if not AdobeProfile.summary(state.adobe_registration).registered then
        print("No Adobe registration is stored.")
        return
    end
    print("WARNING: resetting Adobe registration can prevent re-use of previously fulfilled loan entitlements.")
    local answer = prompt("Reset Adobe registration? [y/N] ")
    if answer and answer:lower() == "y" then
        AdobeProfile.reset(state)
        save_state()
        print("Adobe registration reset. Libby credentials were not changed.")
    else
        print("Cancelled.")
    end
end

local function libby_settings_menu()
    while true do
        clear_screen()
        print("Libby Setup")
        print("-----------")
        print("1. Authentication")
        print("2. Reset")
        print("0. Back")

        local choice = prompt("\nChoice: ")
        if choice == "0" or choice == nil then
            return
        elseif choice == "1" then
            generate_setup_code()
            pause()
        elseif choice == "2" then
            reset_libby()
            pause()
        else
            print("Unknown choice.")
            pause()
        end
    end
end

local function adobe_settings_menu()
    while true do
        clear_screen()
        print("Adobe Setup")
        print("-----------")
        print("1. Adobe Status")
        print("2. Adobe Export")
        print("3. Adobe Import")
        print("4. Reset")
        print("0. Back")

        local choice = prompt("\nChoice: ")
        if choice == "0" or choice == nil then
            return
        elseif choice == "1" then
            adobe_status()
            pause()
        elseif choice == "2" then
            export_adobe()
            pause()
        elseif choice == "3" then
            import_adobe()
            pause()
        elseif choice == "4" then
            reset_adobe()
            pause()
        else
            print("Unknown choice.")
            pause()
        end
    end
end

local function storage_template()
    return state.book_path_template or PathTemplate.DEFAULT_TEMPLATE
end

local function storage_preview_model()
    return {
        title = "Example Book",
        author = "Terry Pratchett",
        authors = {
            { name = "Terry Pratchett", firstName = "Terry", lastName = "Pratchett" },
            { name = "Neil Gaiman", firstName = "Neil", lastName = "Gaiman" },
        },
        library = "Example Library",
        series = "Example Series",
        series_index = "1",
    }
end

local function book_storage_menu()
    while true do
        clear_screen()
        print("Book Storage")
        print("------------")
        print("Template: " .. storage_template())
        print("")
        print("1. Change destination template")
        print("2. Available tokens")
        print("3. Preview")
        print("4. Reset to default")
        print("0. Back")

        local choice = prompt("\nChoice: ")
        if choice == "0" or choice == nil then
            return
        elseif choice == "1" then
            local value = prompt("New template (blank cancels): ")
            if value and value ~= "" then
                local valid, validation_err = PathTemplate.validate(value)
                if valid then
                    state.book_path_template = value
                    save_state()
                else
                    print("Template not saved: " .. tostring(validation_err))
                end
            end
            pause()
        elseif choice == "2" then
            for _, token in ipairs(PathTemplate.tokens()) do print(token) end
            pause()
        elseif choice == "3" then
            local preview = PathTemplate.resolve(storage_template(), storage_preview_model(), { home = ".", ext = "epub" })
            print("\nCLI preview: " .. preview)
            print("KOReader replaces {home} with its configured Home folder.")
            pause()
        elseif choice == "4" then
            state.book_path_template = nil
            save_state()
            pause()
        else
            print("Unknown choice.")
            pause()
        end
    end
end

local function settings_menu()
    while true do
        clear_screen()
        print("Settings")
        print("--------")
        print("1. Libby Setup")
        print("2. Adobe Setup")
        print("3. Book Storage")
        print("0. Back")

        local choice = prompt("\nChoice: ")
        if choice == "0" or choice == nil then
            return
        elseif choice == "1" then
            libby_settings_menu()
        elseif choice == "2" then
            adobe_settings_menu()
        elseif choice == "3" then
            book_storage_menu()
        else
            print("Unknown choice.")
            pause()
        end
    end
end

while true do
    clear_screen()
    print("Libby CLI Dashboard")
    print("-------------------")
    print("Libby: " .. (LibbyState.is_authenticated(state) and "authenticated" or "not authenticated"))
    print("Adobe: " .. (AdobeProfile.summary(state.adobe_registration).registered and "registered" or "not registered"))
    print("")
    print("1. Library cards")
    print("2. Loans")
    print("3. Settings")
    print("0. Exit")

    local choice = prompt("\nChoice: ")
    if choice == "0" or choice == nil then
        break
    elseif choice == "1" then
        clear_screen()
        list_cards()
        pause()
    elseif choice == "2" then
        list_loans()
    elseif choice == "3" then
        settings_menu()
    else
        print("Unknown choice.")
        pause()
    end
end
