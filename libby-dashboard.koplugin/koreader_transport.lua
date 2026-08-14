local KOReaderTransport = {}
KOReaderTransport.__index = KOReaderTransport

local function url_encode(value)
    value = tostring(value or "")
    return (value:gsub("([^%w%-_%.~])", function(ch)
        return string.format("%%%02X", string.byte(ch))
    end))
end

local function query_string(query)
    if type(query) ~= "table" then return "" end
    local keys = {}
    for key, value in pairs(query) do
        if value ~= nil then table.insert(keys, key) end
    end
    table.sort(keys)
    local parts = {}
    for _, key in ipairs(keys) do
        table.insert(parts, url_encode(key) .. "=" .. url_encode(query[key]))
    end
    return table.concat(parts, "&")
end

function KOReaderTransport.new(options)
    options = options or {}
    return setmetatable({
        https = options.https,
        ltn12 = options.ltn12,
        json_encode = options.json_encode,
        json_decode = options.json_decode,
        mime = options.mime,
        socketutil = options.socketutil,
        tls_options = options.tls_options or {},
    }, KOReaderTransport)
end

function KOReaderTransport:_load()
    if not self.https then
        local ok, module = pcall(require, "ssl.https")
        if not ok then return nil, "KOReader HTTPS support is unavailable" end
        self.https = module
    end
    if not self.ltn12 then
        local ok, module = pcall(require, "ltn12")
        if not ok then return nil, "KOReader ltn12 support is unavailable" end
        self.ltn12 = module
    end
    if not self.socketutil then
        local ok, module = pcall(require, "socketutil")
        if ok then self.socketutil = module end
    end
    if not self.mime then
        local ok, module = pcall(require, "mime")
        if ok then self.mime = module end
    end
    if not self.json_encode or not self.json_decode then
        local ok, rapidjson = pcall(require, "rapidjson")
        if ok then
            self.json_encode = self.json_encode or rapidjson.encode
            self.json_decode = self.json_decode or rapidjson.decode
        end
    end
    if not self.json_encode or not self.json_decode then
        return nil, "KOReader JSON support is unavailable"
    end
    return true
end

function KOReaderTransport:base64url_decode(value)
    local loaded, load_err = self:_load()
    if not loaded then return nil, load_err end
    if type(value) ~= "string" then return nil, "base64url input is missing" end
    if not self.mime or type(self.mime.unb64) ~= "function" then return nil, "KOReader MIME support is unavailable" end

    local normalized = value:gsub("-", "+"):gsub("_", "/")
    local remainder = #normalized % 4
    if remainder == 2 then
        normalized = normalized .. "=="
    elseif remainder == 3 then
        normalized = normalized .. "="
    elseif remainder == 1 then
        return nil, "invalid base64url input length"
    end

    local decoded = self.mime.unb64(normalized)
    if not decoded then return nil, "base64url decode failed" end
    return decoded
end

function KOReaderTransport:request_sequence(requests)
    local loaded, load_err = self:_load()
    if not loaded then return nil, load_err end
    if type(requests) ~= "table" or #requests == 0 then return nil, "requests are required" end

    -- LuaSec's request() accepts a custom create callback. Reusing one connected
    -- TLS socket through that callback keeps every request in this sequence on
    -- the same HTTP/1.1 connection, which Libby's protected fulfillment requires.
    local socket_ok, socket = pcall(require, "socket")
    local http_ok, http = pcall(require, "socket.http")
    if not socket_ok or not http_ok or type(self.https.tcp) ~= "function" or type(http.open) ~= "function" then
        return nil, "KOReader persistent HTTPS support is unavailable"
    end

    local first = requests[1]
    local base = tostring(first.base_url or "")
    local host = base:match("^https://([^/:]+)")
    local port = tonumber(base:match("^https://[^/:]+:(%d+)")) or 443
    if not host then return nil, "Persistent HTTPS sequence requires an HTTPS base URL" end

    local params = { protocol = "tlsv1_2", verify = "none", options = "all" }
    for key, value in pairs(self.tls_options) do params[key] = value end
    local connection
    local opened, open_err = pcall(function()
        connection = http.open(host, port, self.https.tcp(params))
    end)
    if not opened or not connection then return nil, tostring(open_err or "Could not open persistent HTTPS connection") end

    local responses = {}

    for index, request_spec in ipairs(requests) do
        local request = request_spec
        if type(request_spec) == "function" then
            request = request_spec(responses)
        end
        if type(request) ~= "table" then connection:close(); return nil, "Persistent HTTPS sequence produced an invalid request" end
        if tostring(request.base_url or "") ~= base then connection:close(); return nil, "Persistent HTTPS sequence cannot change origin" end
        local url = base .. tostring(request.path or "")
        local query = query_string(request.query)
        if query ~= "" then url = url .. "?" .. query end
        local headers = {}
        for key, value in pairs(request.headers or {}) do headers[key] = value end
        headers["Accept-Encoding"] = "identity"
        headers["Connection"] = index == #requests and "close" or "keep-alive"
        local body
        if request.json ~= nil then
            local ok, encoded = pcall(self.json_encode, request.json)
            if not ok or type(encoded) ~= "string" then connection:close(); return nil, "Could not encode JSON request" end
            body = encoded
            headers["Content-Type"] = "application/json; charset=UTF-8"
            headers["Content-Length"] = tostring(#body)
        end
        headers["Host"] = host
        if not headers["Content-Length"] and (request.method == "POST" or request.method == "PUT") then
            headers["Content-Length"] = "0"
        end
        local uri = tostring(request.path or "")
        if uri == "" then uri = "/" end
        if query ~= "" then uri = uri .. "?" .. query end
        local chunks = {}
        local ok, status, response_headers, status_line = pcall(function()
            connection:sendrequestline(request.method or "GET", uri)
            connection:sendheaders(headers)
            if body then connection:sendbody(headers, self.ltn12.source.string(body)) end
            local code, line = connection:receivestatusline()
            local received_headers = connection:receiveheaders()
            connection:receivebody(received_headers, (self.ltn12.sink.table(chunks)))
            return code, received_headers, line
        end)
        if not ok then connection:close(); return nil, tostring(status or "HTTPS request failed") end
        status = tonumber(status)
        if not status then connection:close(); return nil, "HTTPS response did not include a numeric status" end
        local raw_body = table.concat(chunks)
        local parsed = raw_body
        if raw_body ~= "" then
            local decode_ok, decoded = pcall(self.json_decode, raw_body)
            if decode_ok then parsed = decoded end
        end
        responses[index] = { status = status, headers = response_headers or {}, status_line = status_line, body = parsed, raw_body = raw_body }
    end
    pcall(function() connection:close() end)
    return responses
end

function KOReaderTransport:request(request)
    local loaded, load_err = self:_load()
    if not loaded then return nil, load_err end
    if type(request) ~= "table" then return nil, "request is required" end

    local url = tostring(request.base_url or "") .. tostring(request.path or "")
    local query = query_string(request.query)
    if query ~= "" then url = url .. "?" .. query end

    local headers = {}
    for key, value in pairs(request.headers or {}) do headers[key] = value end
    headers["Accept-Encoding"] = "identity"

    local body
    if request.json ~= nil then
        local ok, encoded = pcall(self.json_encode, request.json)
        if not ok or type(encoded) ~= "string" then return nil, "Could not encode JSON request" end
        body = encoded
        headers["Content-Type"] = "application/json; charset=UTF-8"
        headers["Content-Length"] = tostring(#body)
    end

    local chunks = {}
    local sink = self.ltn12.sink.table(chunks)
    if self.socketutil and type(self.socketutil.table_sink) == "function" then
        sink = self.socketutil.table_sink(chunks)
    end
    local spec = {
        url = url,
        method = request.method or "GET",
        headers = headers,
        source = body and self.ltn12.source.string(body) or nil,
        sink = sink,
        redirect = false,
    }
    for key, value in pairs(self.tls_options) do spec[key] = value end

    if self.socketutil and type(self.socketutil.set_timeout) == "function" then
        self.socketutil:set_timeout(self.socketutil.LARGE_BLOCK_TIMEOUT, self.socketutil.LARGE_TOTAL_TIMEOUT)
    end
    local ok, status_or_err, response_headers, status_line = self.https.request(spec)
    if self.socketutil and type(self.socketutil.reset_timeout) == "function" then
        self.socketutil:reset_timeout()
    end

    if not ok then return nil, tostring(status_or_err or "HTTPS request failed") end
    local status = tonumber(status_or_err)
    if not status then return nil, "HTTPS response did not include a numeric status" end

    local raw_body = table.concat(chunks)
    local parsed = raw_body
    if raw_body ~= "" then
        local decode_ok, decoded = pcall(self.json_decode, raw_body)
        if decode_ok then parsed = decoded end
    end

    return {
        status = status,
        headers = response_headers or {},
        status_line = status_line,
        body = parsed,
        raw_body = raw_body,
    }
end

return KOReaderTransport
