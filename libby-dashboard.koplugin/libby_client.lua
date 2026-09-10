local LibbyClient = {}
LibbyClient.__index = LibbyClient

LibbyClient.SENTRY_BASE = "https://sentry.libbyapp.com"
LibbyClient.TAGS_BASE = "https://vandal.libbyapp.com"
LibbyClient.THUNDER_BASE = "https://thunder.api.overdrive.com/v2"
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

local function url_encode_component(value)
    value = tostring(value or "")
    return (value:gsub("([^%w%-_%.~])", function(ch)
        return string.format("%%%02X", string.byte(ch))
    end))
end

local function contains_text(value, needle, depth)
    depth = tonumber(depth) or 0
    if depth > 6 then return false end
    if type(value) == "string" then
        return value:lower():find(needle, 1, true) ~= nil
    end
    if type(value) ~= "table" then return false end
    for key, child in pairs(value) do
        if contains_text(key, needle, depth + 1) or contains_text(child, needle, depth + 1) then return true end
    end
    return false
end

local function is_notify_me_tag(tag)
    if type(tag) ~= "table" then return false end
    if contains_text(tag.behaviors, "notify-me") then return true end
    return contains_text(tag, "subscription") and tostring(tag.name or ""):lower():find("notify", 1, true) ~= nil
end

local function tagging_may_be_magazine(tagging)
    if type(tagging) ~= "table" then return false end
    local format = tostring(tagging.titleFormat or ""):lower()
    if format == "" then return true end
    if format:find("magazine", 1, true) or format:find("periodical", 1, true) then return true end
    if format:find("audio", 1, true) or format:find("ebook", 1, true) or format:find("kindle", 1, true) then return false end
    return true
end

local function media_is_magazine(media)
    if type(media) ~= "table" then return false end
    if contains_text(media.type, "magazine") or contains_text(media.type, "periodical") then return true end
    return contains_text(media.formats, "magazine") or contains_text(media.formats, "periodical")
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
        base_url = options.base_url or LibbyClient.SENTRY_BASE,
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

function LibbyClient:return_loan(card_id, loan_id)
    if card_id == nil or tostring(card_id) == "" then return nil, "Loan card id is missing" end
    if loan_id == nil or tostring(loan_id) == "" then return nil, "Loan id is missing" end

    local path = "/card/" .. tostring(card_id) .. "/loan/" .. tostring(loan_id)
    local response, err = self:_request("DELETE", path, { identity = self.identity })
    if not response then return nil, err end

    if response.status == 403 and response_result(response) == "missing_chip" then
        local refreshed, refresh_err = self:get_chip(true, true)
        if not refreshed then return nil, refresh_err end
        response, err = self:_request("DELETE", path, { identity = self.identity })
        if not response then return nil, err end
    end

    if response.status < 200 or response.status >= 300 then
        return nil, "Libby return failed with HTTP " .. tostring(response.status)
    end
    return true
end

function LibbyClient:cancel_hold(card_id, title_id)
    if card_id == nil or tostring(card_id) == "" then return nil, "Hold card id is missing" end
    if title_id == nil or tostring(title_id) == "" then return nil, "Hold title id is missing" end

    local path = "/card/" .. tostring(card_id) .. "/hold/" .. tostring(title_id)
    local response, err = self:_request("DELETE", path, { identity = self.identity })
    if not response then return nil, err end

    if response.status == 403 and response_result(response) == "missing_chip" then
        local refreshed, refresh_err = self:get_chip(true, true)
        if not refreshed then return nil, refresh_err end
        response, err = self:_request("DELETE", path, { identity = self.identity })
        if not response then return nil, err end
    end

    if response.status < 200 or response.status >= 300 then
        return nil, "Libby cancel hold failed with HTTP " .. tostring(response.status)
    end
    return true
end

function LibbyClient:borrow_title(card_id, title_id, title_format, days, is_lucky_day_loan)
    if card_id == nil or tostring(card_id) == "" then return nil, "Borrow card id is missing" end
    if title_id == nil or tostring(title_id) == "" then return nil, "Borrow title id is missing" end
    if title_format == nil or tostring(title_format) == "" then return nil, "Borrow title format is missing" end
    days = math.floor(tonumber(days) or 21)
    if days <= 0 then return nil, "Borrow period must be positive" end

    local path = "/card/" .. tostring(card_id) .. "/loan/" .. tostring(title_id)
    local payload = { period = days, units = "days", title_format = tostring(title_format) }
    if is_lucky_day_loan == true then payload.lucky_day = 1 end
    local response, err = self:_request("POST", path, { identity = self.identity, json = payload })
    if not response then return nil, err end

    if response.status == 403 and response_result(response) == "missing_chip" then
        local refreshed, refresh_err = self:get_chip(true, true)
        if not refreshed then return nil, refresh_err end
        response, err = self:_request("POST", path, { identity = self.identity, json = payload })
        if not response then return nil, err end
    end

    if response.status < 200 or response.status >= 300 then
        return nil, "Libby borrow failed with HTTP " .. tostring(response.status)
    end
    return type(response.body) == "table" and response.body or true
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

function LibbyClient:tags()
    local response, err = self:_request("GET", "/tags", {
        base_url = LibbyClient.TAGS_BASE,
        identity = self.identity,
    })
    if not response then return nil, err end
    if response.status == 403 and response_result(response) == "missing_chip" then
        local refreshed, refresh_err = self:get_chip(true, true)
        if not refreshed then return nil, refresh_err end
        response, err = self:_request("GET", "/tags", {
            base_url = LibbyClient.TAGS_BASE,
            identity = self.identity,
        })
        if not response then return nil, err end
    end
    if response.status ~= 200 then return nil, "Libby tags failed with HTTP " .. tostring(response.status) end
    return type(response.body) == "table" and response.body or {}
end

function LibbyClient:tag(tag_id, tag_name, start_index, end_index)
    if type(self.transport.base64_encode) ~= "function" then
        return nil, "KOReader transport does not support base64 encoding"
    end
    local encoded_name, encode_err = self.transport:base64_encode(tostring(tag_name or ""))
    if not encoded_name then return nil, encode_err end
    local path = "/tag/" .. url_encode_component(tag_id) .. "/" .. url_encode_component(encoded_name)
    local response, err = self:_request("GET", path, {
        base_url = LibbyClient.TAGS_BASE,
        identity = self.identity,
        query = {
            enc = "1",
            sort = "newest",
            range = tostring(tonumber(start_index) or 0) .. "..." .. tostring(tonumber(end_index) or 100),
        },
    })
    if not response then return nil, err end
    if response.status ~= 200 then return nil, "Libby tag details failed with HTTP " .. tostring(response.status) end
    return type(response.body) == "table" and response.body or {}
end

function LibbyClient:media_bulk(title_ids)
    if type(title_ids) ~= "table" or #title_ids == 0 then return {} end
    local ids = {}
    for _, id in ipairs(title_ids) do
        if id ~= nil and tostring(id) ~= "" then table.insert(ids, tostring(id)) end
    end
    if #ids == 0 then return {} end
    local response, err = self:_request("GET", "/media/bulk", {
        base_url = LibbyClient.THUNDER_BASE,
        query = {
            titleIds = table.concat(ids, ","),
            ["x-client-id"] = "dewey",
        },
    })
    if not response then return nil, err end
    if response.status ~= 200 then return nil, "OverDrive magazine lookup failed with HTTP " .. tostring(response.status) end
    return type(response.body) == "table" and response.body or {}
end

function LibbyClient:magazine_subscriptions()
    local tag_state, tag_err = self:tags()
    if not tag_state then return nil, tag_err end

    local taggings = {}
    local seen_taggings = {}
    local function add_tagging(tagging)
        if not tagging_may_be_magazine(tagging) then return end
        local title_id = type(tagging) == "table" and tagging.titleId or nil
        if title_id == nil or tostring(title_id) == "" then return end
        local key = tostring(title_id) .. "|" .. tostring(tagging.cardId or "")
        if seen_taggings[key] then return end
        seen_taggings[key] = true
        table.insert(taggings, tagging)
    end

    for _, tag in ipairs(type(tag_state.tags) == "table" and tag_state.tags or {}) do
        if is_notify_me_tag(tag) then
            local initial = type(tag.taggings) == "table" and tag.taggings or {}
            local total = tonumber(tag.totalTaggings) or #initial
            if total <= #initial then
                for _, tagging in ipairs(initial) do add_tagging(tagging) end
            else
                local page_size = 100
                local start_index = 0
                while start_index < total do
                    local detail, detail_err = self:tag(tag.uuid, tag.name, start_index, math.min(total, start_index + page_size))
                    if not detail then return nil, detail_err end
                    local detail_tag = type(detail.tag) == "table" and detail.tag or {}
                    local page = type(detail_tag.taggings) == "table" and detail_tag.taggings or {}
                    for _, tagging in ipairs(page) do add_tagging(tagging) end
                    if #page == 0 then break end
                    start_index = start_index + page_size
                end
            end
        end
    end

    if #taggings == 0 then return {} end
    local by_tagged_title = {}
    local unique_tagged_ids = {}
    for _, tagging in ipairs(taggings) do
        local id = tostring(tagging.titleId)
        if not by_tagged_title[id] then
            by_tagged_title[id] = {}
            table.insert(unique_tagged_ids, id)
        end
        table.insert(by_tagged_title[id], tagging)
    end

    -- Libby has used both shapes for magazine Notify Me taggings in the wild:
    -- some taggings contain a parent magazine title id, while current Libby
    -- clients may tag the current issue id directly. Resolve the tagged media
    -- first, associate it by either its id or parentMagazineTitleId, then only
    -- follow recentIssues when OverDrive tells us a newer issue exists.
    local result = {}
    local emitted = {}
    local latest_matches = {}
    local latest_issue_ids = {}

    local function append_matches(target, source)
        for _, tagging in pairs(source or {}) do
            local key = tostring(tagging.titleId or "") .. "|" .. tostring(tagging.cardId or "")
            if not target[key] then target[key] = tagging end
        end
    end

    local function matches_for(media)
        local matches = {}
        append_matches(matches, by_tagged_title[tostring(media.id or "")])
        append_matches(matches, by_tagged_title[tostring(media.parentMagazineTitleId or "")])
        return matches
    end

    local function emit(media, matches)
        local issue_id = tostring(media.id or "")
        for _, tagging in pairs(matches or {}) do
            local key = issue_id .. "|" .. tostring(tagging.cardId or "")
            if not emitted[key] then
                emitted[key] = true
                local copy = copy_table(media)
                copy.cardId = tagging.cardId
                copy.websiteId = tagging.websiteId
                copy.magazineSubscription = true
                copy.subscriptionTitleId = tagging.titleId
                table.insert(result, copy)
            end
        end
    end

    for batch_start = 1, #unique_tagged_ids, 24 do
        local batch = {}
        for index = batch_start, math.min(#unique_tagged_ids, batch_start + 23) do
            table.insert(batch, unique_tagged_ids[index])
        end
        local tagged_media, media_err = self:media_bulk(batch)
        if not tagged_media then return nil, media_err end
        for _, media in ipairs(tagged_media) do
            if media_is_magazine(media) then
                local matches = matches_for(media)
                if next(matches) ~= nil then
                    local recent = type(media.recentIssues) == "table" and media.recentIssues or {}
                    local latest_id = type(recent[1]) == "table" and recent[1].id or nil
                    if latest_id ~= nil and tostring(latest_id) ~= "" and tostring(latest_id) ~= tostring(media.id or "") then
                        latest_id = tostring(latest_id)
                        if not latest_matches[latest_id] then
                            latest_matches[latest_id] = {}
                            table.insert(latest_issue_ids, latest_id)
                        end
                        append_matches(latest_matches[latest_id], matches)
                    else
                        emit(media, matches)
                    end
                end
            end
        end
    end

    for batch_start = 1, #latest_issue_ids, 24 do
        local batch = {}
        for index = batch_start, math.min(#latest_issue_ids, batch_start + 23) do
            table.insert(batch, latest_issue_ids[index])
        end
        local issue_items, issue_err = self:media_bulk(batch)
        if not issue_items then return nil, issue_err end
        for _, media in ipairs(issue_items) do
            if media_is_magazine(media) then
                emit(media, latest_matches[tostring(media.id or "")])
            end
        end
    end
    return result
end

function LibbyClient:_recover_fulfillment_on_same_connection(path, return_href)
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
    if not href:match("^https://") then return nil, "Libby returned a non-HTTPS fulfillment URL" end
    if return_href then return href end
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

function LibbyClient:fulfill_open_loan(card_id, loan_id, format_id)
    if not self.identity then return nil, "Libby identity is missing" end
    if not card_id or not loan_id or not format_id then return nil, "Loan fulfillment identifiers are missing" end
    if format_id ~= "ebook-epub-open" and format_id ~= "ebook-pdf-open" then
        return nil, "Loan format is not an open EPUB/PDF format"
    end

    local path = "/card/" .. tostring(card_id) .. "/loan/" .. tostring(loan_id) .. "/fulfill/" .. tostring(format_id)
    local response, err = self:_request("GET", path, { identity = self.identity })
    if not response then return nil, err end
    if response.status == 403 and response_result(response) == "missing_chip" then
        local recovered_href, recover_err = self:_recover_fulfillment_on_same_connection(path, true)
        if not recovered_href then return nil, recover_err end
        response = { status = 200, body = { fulfill = { href = recovered_href } } }
    end
    if response.status ~= 200 then return nil, "Libby fulfillment failed with HTTP " .. tostring(response.status) end

    local href = type(response.body) == "table" and response.body.fulfill and response.body.fulfill.href
    if type(href) ~= "string" or href == "" then return nil, "Libby fulfillment response did not contain fulfill.href" end
    if not href:match("^https://") then return nil, "Libby returned a non-HTTPS fulfillment URL" end

    local payload, download_err = self.transport:request({
        method = "GET",
        base_url = href,
        path = "",
        headers = { ["User-Agent"] = self.user_agent, ["Accept"] = "*/*" },
    })
    if not payload then return nil, download_err end
    if payload.status ~= 200 then return nil, "Open ebook download failed with HTTP " .. tostring(payload.status) end
    if type(payload.raw_body) ~= "string" or payload.raw_body == "" then return nil, "Open ebook download returned an empty body" end
    return payload.raw_body
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
