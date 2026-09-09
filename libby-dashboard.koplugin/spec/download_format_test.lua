package.path = "./libby-dashboard.koplugin/?.lua;" .. package.path

local LibbyState = require("libby_state")
local LoanModel = require("loan_model")

local function loan_with(...)
    local formats = {}
    for _, id in ipairs({ ... }) do
        formats[#formats + 1] = { id = id }
    end
    return { id = "loan-1", title = "Test", formats = formats }
end

assert(LibbyState.preferred_download_format(loan_with("ebook-epub-open")) == "ebook-epub-open")
assert(LibbyState.preferred_download_format(loan_with("ebook-pdf-open")) == "ebook-pdf-open")
assert(LibbyState.preferred_download_format(loan_with("ebook-pdf-open", "ebook-epub-adobe")) == "ebook-epub-adobe")
assert(LibbyState.preferred_download_format(loan_with("ebook-epub-open", "ebook-pdf-adobe")) == "ebook-pdf-adobe")
assert(LibbyState.preferred_download_format(loan_with("magazine-overdrive")) == nil)
assert(LibbyState.preferred_download_format(loan_with("ebook-media-do")) == nil)

local open_pdf = LoanModel.from_loan(loan_with("ebook-pdf-open"), {})
assert(open_pdf.download_format == "ebook-pdf-open")
assert(open_pdf.adobe_format == nil, "open PDF must not be routed through Adobe fulfillment")

local adobe_pdf = LoanModel.from_loan(loan_with("ebook-pdf-adobe"), {})
assert(adobe_pdf.download_format == "ebook-pdf-adobe")
assert(adobe_pdf.adobe_format == "ebook-pdf-adobe")

print("download_format_test: ok")
