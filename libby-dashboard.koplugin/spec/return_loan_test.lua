package.path = "./libby-dashboard.koplugin/?.lua;" .. package.path

local LibbyClient = require("libby_client")

local calls = {}
local transport = {}
function transport:request(request)
    calls[#calls + 1] = request
    return { status = 204, body = {} }
end

local client = LibbyClient.new{
    transport = transport,
    identity = "test-identity",
}

local ok, err = client:return_loan("card-123", "loan-456")
assert(ok == true, tostring(err))
assert(#calls == 1)
assert(calls[1].method == "DELETE")
assert(calls[1].path == "/card/card-123/loan/loan-456")
assert(calls[1].headers.Authorization == "Bearer test-identity")

local missing_card, missing_card_err = client:return_loan(nil, "loan-456")
assert(missing_card == nil)
assert(missing_card_err == "Loan card id is missing")
assert(#calls == 1, "invalid return must not make a network request")

local failing_transport = {}
function failing_transport:request(request)
    return { status = 409, body = {} }
end
local failing_client = LibbyClient.new{ transport = failing_transport, identity = "test-identity" }
local failed, failed_err = failing_client:return_loan("card-123", "loan-456")
assert(failed == nil)
assert(failed_err == "Libby return failed with HTTP 409")

print("return_loan_test: ok")
