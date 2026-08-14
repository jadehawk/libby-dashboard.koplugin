local cjson = require("cjson")
local https = require("ssl.https")
local ltn12 = require("ltn12")
local mime = require("mime")

local HttpTransport = {}
HttpTransport.__index = HttpTransport

local function url_encode(value)
    value = tostring(value or "")
    return (value:gsub("([^%w%-_%.~])", function(ch)
        return string.format("%%%02X", string.byte(ch))
    end))
end

local function build_query(query)
    if type(query) ~= "table" then
        return ""
    end

    local keys = {}
    for key in pairs(query) do
        table.insert(keys, key)
    end
    table.sort(keys)

    local parts = {}
    for _, key in ipairs(keys) do
        table.insert(parts, url_encode(key) .. "=" .. url_encode(query[key]))
    end
    return table.concat(parts, "&")
end

function HttpTransport.new(options)
    options = options or {}
    return setmetatable({
        timeout = options.timeout or 30,
        cafile = options.cafile or "/etc/ssl/certs/ca-certificates.crt",
    }, HttpTransport)
end

function HttpTransport:base64url_decode(value)
    if type(value) ~= "string" then
        return nil, "base64url input is missing"
    end

    local normalized = value:gsub("-", "+"):gsub("_", "/")
    local remainder = #normalized % 4
    if remainder == 2 then
        normalized = normalized .. "=="
    elseif remainder == 3 then
        normalized = normalized .. "="
    elseif remainder == 1 then
        return nil, "invalid base64url input length"
    end

    local decoded = mime.unb64(normalized)
    if not decoded then
        return nil, "base64url decode failed"
    end
    return decoded
end

function HttpTransport:request(request)
    if type(request) ~= "table" then
        return nil, "request is required"
    end

    local url = tostring(request.base_url or "") .. tostring(request.path or "")
    local query = build_query(request.query)
    if query ~= "" then
        url = url .. "?" .. query
    end

    local headers = {}
    for key, value in pairs(request.headers or {}) do
        headers[key] = value
    end
    -- Avoid requiring a gzip decoder in the standalone Lua runtime.
    headers["Accept-Encoding"] = "identity"

    local body
    if request.json ~= nil then
        body = cjson.encode(request.json)
        headers["Content-Type"] = "application/json; charset=UTF-8"
        headers["Content-Length"] = tostring(#body)
    end

    local chunks = {}
    local previous_timeout = https.TIMEOUT
    https.TIMEOUT = self.timeout
    local ok, status_or_err, response_headers, status_line = https.request({
        url = url,
        method = request.method or "GET",
        headers = headers,
        source = body and ltn12.source.string(body) or nil,
        sink = ltn12.sink.table(chunks),
        protocol = "tlsv1_2",
        verify = "peer",
        cafile = self.cafile,
        options = "all",
    })
    https.TIMEOUT = previous_timeout

    if not ok then
        return nil, tostring(status_or_err or "HTTPS request failed")
    end

    local status = tonumber(status_or_err)
    if not status then
        return nil, "HTTPS response did not include a numeric status"
    end

    local raw_body = table.concat(chunks)
    local parsed_body = raw_body
    local content_type = response_headers and (response_headers["content-type"] or response_headers["Content-Type"])
    if raw_body ~= "" and (not content_type or content_type:find("json", 1, true)) then
        local decode_ok, decoded = pcall(cjson.decode, raw_body)
        if decode_ok then
            parsed_body = decoded
        end
    end

    return {
        status = status,
        headers = response_headers or {},
        status_line = status_line,
        body = parsed_body,
        raw_body = raw_body,
    }
end

function HttpTransport.json_decode(value)
    return cjson.decode(value)
end

function HttpTransport.json_encode(value)
    return cjson.encode(value)
end

return HttpTransport
