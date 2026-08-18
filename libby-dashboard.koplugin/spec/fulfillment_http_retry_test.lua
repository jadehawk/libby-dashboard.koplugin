package.path = "./libby-dashboard.koplugin/?.lua;" .. package.path

package.loaded["adobe.fulfillment"] = nil

local responses = {}
local request_count = 0
local sleep_calls = {}
local sent_bodies = {}

package.preload["datastorage"] = function()
    return { getDataDir = function() return "/tmp" end }
end
package.preload["socket.http"] = function()
    return {
        request = function(request)
            request_count = request_count + 1
            if request.source then
                local chunks = {}
                while true do
                    local chunk = request.source()
                    if chunk == nil then break end
                    chunks[#chunks + 1] = chunk
                end
                sent_bodies[#sent_bodies + 1] = table.concat(chunks)
            end
            local response = table.remove(responses, 1)
            assert(response, "missing mocked HTTP response")
            if request.sink and response.body then
                request.sink(response.body)
                request.sink(nil)
            end
            return 1, response.status
        end,
    }
end
package.preload["libs/libkoreader-lfs"] = function()
    return { attributes = function() end, mkdir = function() end }
end
package.preload["ltn12"] = function()
    return {
        source = {
            string = function(value)
                local sent = false
                return function()
                    if sent then return nil end
                    sent = true
                    return value
                end
            end,
        },
    }
end
package.preload["logger"] = function()
    return { info = function() end, warn = function() end }
end
package.preload["socket"] = function()
    return {
        skip = function(n, ...)
            return select(n + 1, ...)
        end,
        sleep = function(seconds)
            sleep_calls[#sleep_calls + 1] = seconds
        end,
    }
end
package.preload["socket.url"] = function()
    return { escape = function(value) return value end }
end
package.preload["socketutil"] = function()
    return {
        USER_AGENT = "test-agent",
        FILE_BLOCK_TIMEOUT = 1,
        FILE_TOTAL_TIMEOUT = 1,
        table_sink = function(buffer)
            return function(chunk)
                if chunk then buffer[#buffer + 1] = chunk end
                return 1
            end, buffer
        end,
        set_timeout = function() end,
        reset_timeout = function() end,
    }
end
package.preload["util"] = function()
    return {}
end
package.preload["adobe.adobe"] = function()
    return { VERSION = { hobbes = "1", os = "test", version = "1" } }
end
package.preload["adobe.util.adobehash"] = function()
    return { ADEPT = "http://ns.adobe.com/adept", digest = function() return "digest" end }
end
package.preload["adobe.util.crypto"] = function() return {} end
package.preload["adobe.util.dom"] = function() return {} end
package.preload["adobe.epub"] = function() return {} end
package.preload["adobe.util.nativecrypto"] = function() return {} end
package.preload["adobe.util.util"] = function()
    return { base64 = { encode = function(v) return v end, decode = function(v) return v end } }
end
package.preload["adobe.util.xml"] = function() return {} end

local fulfillment = require("adobe.fulfillment")
assert(type(fulfillment._requestToString) == "function")

responses = {
    { status = 502, body = "bad gateway" },
    { status = 200, body = "<success/>" },
}
request_count = 0
sleep_calls = {}
sent_bodies = {}
local body, code = fulfillment._requestToString({
    url = "https://example.test/Fulfill",
    method = "POST",
    headers = {},
}, "signed-body")
assert(body == "<success/>")
assert(code == 200)
assert(request_count == 2, "502 should be retried once before succeeding")
assert(#sleep_calls == 1 and sleep_calls[1] == 0.5)
assert(#sent_bodies == 2 and sent_bodies[1] == "signed-body" and sent_bodies[2] == "signed-body", "POST body must be rebuilt for every retry")

responses = {
    { status = 503, body = "unavailable" },
    { status = 503, body = "unavailable" },
    { status = 503, body = "unavailable" },
}
request_count = 0
sleep_calls = {}
local failed, err = fulfillment._requestToString({ url = "https://example.test/Auth", method = "GET", headers = {} })
assert(failed == nil)
assert(err == "HTTP 503 after 3 attempts")
assert(request_count == 3, "transient failure should stop after three attempts")
assert(#sleep_calls == 2 and sleep_calls[1] == 0.5 and sleep_calls[2] == 1)

responses = {
    { status = 500, body = "server error" },
}
request_count = 0
sleep_calls = {}
local nontransient, nontransient_err = fulfillment._requestToString({ url = "https://example.test/Auth", method = "GET", headers = {} })
assert(nontransient == nil)
assert(nontransient_err == "HTTP 500")
assert(request_count == 1, "non-transient HTTP errors must not be retried")
assert(#sleep_calls == 0)

print("fulfillment_http_retry_test: ok")
