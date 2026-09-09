package.path = "./libby-dashboard.koplugin/?.lua;" .. package.path

local LibbyClient = require("libby_client")

local calls = {}
local payload = "%PDF-1.7\nopen-pdf"
local transport = {}
function transport:request(request)
    calls[#calls + 1] = request
    if request.path == "/card/card-1/loan/loan-1/fulfill/ebook-pdf-open" then
        return {
            status = 200,
            body = { fulfill = { href = "https://example.test/book.pdf" } },
        }
    end
    if request.base_url == "https://example.test/book.pdf" then
        return { status = 200, raw_body = payload }
    end
    return nil, "unexpected request"
end

local client = LibbyClient.new{
    transport = transport,
    identity = "test-identity",
}

local body, err = client:fulfill_open_loan("card-1", "loan-1", "ebook-pdf-open")
assert(body == payload, tostring(err))
assert(#calls == 2)
assert(calls[1].path == "/card/card-1/loan/loan-1/fulfill/ebook-pdf-open")
assert(calls[1].headers.Authorization == "Bearer test-identity")
assert(calls[2].base_url == "https://example.test/book.pdf")
assert(calls[2].headers.Accept == "*/*")

local invalid, invalid_err = client:fulfill_open_loan("card-1", "loan-1", "ebook-media-do")
assert(invalid == nil)
assert(invalid_err == "Loan format is not an open EPUB/PDF format")
assert(#calls == 2, "invalid open format must not make a network request")

print("open_format_fulfillment_test: ok")
