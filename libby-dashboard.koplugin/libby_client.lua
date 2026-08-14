local LibbyClient = {}
LibbyClient.__index = LibbyClient

LibbyClient.SENTRY_BASE = "https://sentry.libbyapp.com"
LibbyClient.CLIENT_VERSION = "d:22.0.3"

local function copy_table(source)
    local result = {}
    if source then
        for key, value in pairs(source) do
            result[key] = value
        end
    end
    return result
end

local function normalize_response(response)
    if type(response) ~= "table" then
        return nil, "Transport returned an invalid response"
    end
    if type(response.status) ~= "number" then
        return nil, "Transport response is missing status"
    end
    return response
end

local function response_result(response)
    if type(response.body) == "table" then
        return response.body.result
    end
end

function LibbyClient.chip_accept_language(identity_token, chip_id)
    local seed = identity_token
    if not seed or seed == "" then
        if chip_id and chip_id ~= "" then
            seed = "xxxxxx" .. chip_id
        else
            seed = "cudlkahllcnsjxhbmddl"
        end
    end

    local chars = {}
    for i = 1, #seed do
        local ch = seed:sub(i, i)
        if ch >= "a" and ch <= "z" then
            table.insert(chars, ch)
        end
    end

    local reversed = {}
    for i = #chars, 1, -1 do
        table.insert(reversed, chars[i])
    end
    local normalized = table.concat(reversed)
    return normalized:sub(5, 6)
end

function LibbyClient.new(options)
    assert(type(options) == "table", "options are required")
    assert(type(options.transport) == "table", "transport is required")
    assert(type(options.transport.request) == "function", "transport.request is required")

    return setmetatable({
        transport = options.transport,
        identity = options.identity,
        json_decode = options.json_decode,
        on_identity = options.on_identity,
        user_agent = options.user_agent or "Mozilla/5.0",
    }, LibbyClient)
end

function LibbyClient:default_headers()
    return {
        ["User-Agent"] = self.user_agent,
        ["Accept"] = "application/json",
        ["Accept-Encoding"] = "gzip",
        ["Referer"] = "https://libbyapp.com/",
        ["Origin"] = "https://libbyapp.com",
        ["Sec-Fetch-Dest"] = "empty",
        ["Sec-Fetch-Mode"] = "cors",
        ["Sec-Fetch-Site"] = "same-site",
        ["Cache-Control"] = "no-cache",
        ["Pragma"] = "no-cache",
    }
end

function LibbyClient:_request(method, path, options)
    options = options or {}
    local headers = self:default_headers()
    for key, value in pairs(options.headers or {}) do
        headers[key] = value
    end
    if options.identity then
        headers["Authorization"] = "Bearer " .. options.identity
    end

    local response, err = self.transport:request({
        method = method,
        base_url = LibbyClient.SENTRY_BASE,
        path = path,
        query = options.query,
        headers = headers,
        json = options.json,
        connection = options.connection,
    })
    if not response then
        return nil, err or "Libby request failed"
    end
    return normalize_response(response)
end

function LibbyClient:_decode_jwt_payload(identity)
    if type(self.json_decode) ~= "function" then
        return nil, "json_decode is required to refresh an authenticated chip"
    end
    if type(identity) ~= "string" then
        return nil, "Identity is missing"
    end

    local payload = identity:match("^[^.]+%.([^.]+)%.")
    if not payload then
        return nil, "Identity is not a JWT"
    end

    local decoder = self.transport.base64url_decode
    if type(decoder) ~= "function" then
        return nil, "transport.base64url_decode is required"
    end
    local decoded, decode_err = decoder(self.transport, payload)
    if not decoded then
        return nil, decode_err or "Could not decode JWT payload"
    end

    local ok, result = pcall(self.json_decode, decoded)
    if not ok or type(result) ~= "table" then
        return nil, "Could not parse JWT payload"
    end
    return result
end

function LibbyClient:short_chip_id(identity)
    local payload, err = self:_decode_jwt_payload(identity)
    if not payload then
        return nil, err
    end
    local chip = payload.chip
    if type(chip) ~= "table" or type(chip.id) ~= "string" then
        return nil, "Identity JWT is missing chip.id"
    end
    return chip.id:match("^([^-]+)")
end

function LibbyClient:_set_identity(identity)
    self.identity = identity
    if type(self.on_identity) == "function" then
        self.on_identity(identity)
    end
end

function LibbyClient:get_chip(authenticated, update_identity)
    local identity = authenticated and self.identity or nil
    local query = {
        c = LibbyClient.CLIENT_VERSION,
        s = "0",
    }
    if authenticated then
        local short_id, err = self:short_chip_id(identity)
        if not short_id then
            return nil, err
        end
        query.v = short_id
    end

    local headers = {
        ["Accept-Language"] = LibbyClient.chip_accept_language(identity),
    }
    local response, err = self:_request("POST", "/chip", {
        query = query,
        headers = headers,
        identity = identity,
    })
    if not response then
        return nil, err
    end
    if response.status ~= 200 then
        return nil, "Libby chip request failed with HTTP " .. tostring(response.status)
    end
    if type(response.body) ~= "table" or type(response.body.identity) ~= "string" then
        return nil, "Libby chip response did not contain an identity"
    end

    if update_identity ~= false then
        self:_set_identity(response.body.identity)
    end
    return response.body
end

function LibbyClient:generate_clone_code()
    local response, err = self:_request("GET", "/chip/clone/code", {
        query = { code = "", role = "pointer" },
        identity = self.identity,
    })
    if not response then
        return nil, err
    end
    if response.status ~= 200 or type(response.body) ~= "table" then
        return nil, "Could not generate Libby setup code"
    end
    if type(response.body.code) ~= "string" then
        return nil, "Libby setup-code response did not contain a code"
    end
    return response.body
end

function LibbyClient:poll_clone_code(code)
    local response, err = self:_request("GET", "/chip/clone/code", {
        query = { code = code, role = "pointer" },
        identity = self.identity,
    })
    if not response then
        return nil, err
    end
    if response.status ~= 200 or type(response.body) ~= "table" then
        return nil, "Could not verify Libby setup code"
    end
    return response.body
end

function LibbyClient:clone_by_blessing(blessing)
    local response, err = self:_request("POST", "/chip/clone", {
        identity = self.identity,
        json = { blessing = blessing },
    })
    if not response then
        return nil, err
    end

    if response.status == 403 and response_result(response) == "missing_chip" then
        local refreshed, refresh_err = self:get_chip(true, true)
        if not refreshed then
            return nil, refresh_err
        end
        response, err = self:_request("POST", "/chip/clone", {
            identity = self.identity,
            json = { blessing = blessing },
        })
        if not response then
            return nil, err
        end
    end

    if response.status ~= 200 then
        return nil, "Libby clone failed with HTTP " .. tostring(response.status)
    end
    return response.body
end

function LibbyClient:sync()
    local response, err = self:_request("GET", "/chip/sync", {
        identity = self.identity,
    })
    if not response then
        return nil, err
    end

    if response.status == 403 and response_result(response) == "missing_chip" then
        local refreshed, refresh_err = self:get_chip(true, true)
        if not refreshed then
            return nil, refresh_err
        end
        response, err = self:_request("GET", "/chip/sync", {
            identity = self.identity,
        })
        if not response then
            return nil, err
        end
    end

    if response.status ~= 200 then
        return nil, "Libby sync failed with HTTP " .. tostring(response.status)
    end
    return response.body
end

function LibbyClient:_recover_fulfillment_on_same_connection(path)
    if type(self.transport.request_sequence) ~= "function" then
        return nil, "KOReader transport does not support persistent fulfillment requests"
    end
    local original_identity = self.identity
    local short_id, short_err = self:short_chip_id(original_identity)
    if not short_id then return nil, short_err end
    local function headers(identity, language)
        local result = self:default_headers()
        result["Authorization"] = "Bearer " .. identity
        result["Connection"] = "keep-alive"
        if language then result["Accept-Language"] = language end
        return result
    end
    local sequence, err = self.transport:request_sequence({
        { method = "GET", base_url = LibbyClient.SENTRY_BASE, path = path, headers = headers(original_identity) },
        function(responses)
            if response_result(responses[1]) ~= "missing_chip" then return nil end
            return { method = "POST", base_url = LibbyClient.SENTRY_BASE, path = "/chip", query = { c = LibbyClient.CLIENT_VERSION, s = "0", v = short_id }, headers = headers(original_identity, LibbyClient.chip_accept_language(original_identity)) }
        end,
        function(responses)
            local chip = responses[2]
            local identity = chip and type(chip.body) == "table" and chip.body.identity
            if type(identity) ~= "string" then return nil end
            return { method = "GET", base_url = LibbyClient.SENTRY_BASE, path = path, headers = headers(identity) }
        end,
    })
    if not sequence then return nil, err end
    local chip = sequence[2]
    local retry = sequence[3]
    local identity = chip and type(chip.body) == "table" and chip.body.identity
    if not chip or chip.status ~= 200 or type(identity) ~= "string" then return nil, "Libby chip recovery failed" end
    if not retry or retry.status ~= 200 then return nil, "Libby fulfillment retry failed with HTTP " .. tostring(retry and retry.status or "unknown") end
    self:_set_identity(identity)
    local href = type(retry.body) == "table" and retry.body.fulfill and retry.body.fulfill.href
    if type(href) ~= "string" or href == "" then return nil, "Libby fulfillment response did not contain fulfill.href" end
    local acsm, download_err = self.transport:request({ method = "GET", base_url = href, path = "", headers = { ["User-Agent"] = self.user_agent, ["Accept"] = "*/*" } })
    if not acsm then return nil, download_err end
    if acsm.status ~= 200 then return nil, "ACSM download failed with HTTP " .. tostring(acsm.status) end
    if type(acsm.raw_body) ~= "string" or acsm.raw_body == "" then return nil, "ACSM download returned an empty body" end
    return acsm.raw_body
end

function LibbyClient:fulfill_adobe_loan(card_id, loan_id, format_id)
    if not self.identity then return nil, "Libby identity is missing" end
    if not card_id or not loan_id or not format_id then return nil, "Loan fulfillment identifiers are missing" end

    local path = "/card/" .. tostring(card_id) .. "/loan/" .. tostring(loan_id) .. "/fulfill/" .. tostring(format_id)
    local response, err = self:_request("GET", path, { identity = self.identity })
    if not response then return nil, err end
    if response.status == 403 and response_result(response) == "missing_chip" then
        return self:_recover_fulfillment_on_same_connection(path)
    end
    if response.status ~= 200 then return nil, "Libby fulfillment failed with HTTP " .. tostring(response.status) end

    local href = type(response.body) == "table" and response.body.fulfill and response.body.fulfill.href
    if type(href) ~= "string" or href == "" then return nil, "Libby fulfillment response did not contain fulfill.href" end
    if not href:match("^https://") then return nil, "Libby returned a non-HTTPS fulfillment URL" end

    local acsm, download_err = self.transport:request({
        method = "GET",
        base_url = href,
        path = "",
        headers = { ["User-Agent"] = self.user_agent, ["Accept"] = "*/*" },
    })
    if not acsm then return nil, download_err end
    if acsm.status ~= 200 then return nil, "ACSM download failed with HTTP " .. tostring(acsm.status) end
    if type(acsm.raw_body) ~= "string" or acsm.raw_body == "" then return nil, "ACSM download returned an empty body" end
    if not acsm.raw_body:find("<", 1, true) then return nil, "ACSM download did not return XML" end
    return acsm.raw_body
end

function LibbyClient:get_cards()
    local state, err = self:sync()
    if not state then
        return nil, err
    end
    return state.cards or {}
end

function LibbyClient:get_loans()
    local state, err = self:sync()
    if not state then
        return nil, err
    end
    return state.loans or {}
end

function LibbyClient:begin_setup()
    local chip, chip_err = self:get_chip(false, true)
    if not chip then
        return nil, chip_err
    end
    return self:generate_clone_code()
end

function LibbyClient:complete_setup(code)
    local poll, poll_err = self:poll_clone_code(code)
    if not poll then
        return nil, poll_err
    end
    if poll.result ~= "fulfilled" or type(poll.blessing) ~= "string" or poll.blessing == "" then
        return nil, "Libby setup code has not been accepted yet"
    end

    local clone, clone_err = self:clone_by_blessing(poll.blessing)
    if not clone then
        return nil, clone_err
    end

    local refreshed, refresh_err = self:get_chip(true, true)
    if not refreshed then
        return nil, refresh_err
    end

    local state, sync_err = self:sync()
    if not state then
        return nil, sync_err
    end
    if state.result ~= "synchronized" or type(state.cards) ~= "table" or #state.cards == 0 then
        return nil, "Libby setup completed but no synchronized library cards were returned"
    end

    return state
end

return LibbyClient
