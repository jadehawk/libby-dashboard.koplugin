package.path = "./libby-dashboard.koplugin/?.lua;" .. package.path

local LoanModel = require("loan_model")

assert(LoanModel.media_type({ formats = { { id = "audiobook-mp3" } } }) == "audiobook")
assert(LoanModel.media_type({ formats = { { id = "magazine-overdrive" } } }) == "magazine")
assert(LoanModel.media_type({ formats = { { id = "ebook-media-do", name = "MediaDo eBook", fulfillmentType = "media-do" } } }) == "comic")
assert(LoanModel.media_type({ formats = { { name = "MP3 Audiobook" } } }) == "audiobook")
assert(LoanModel.media_type({ formats = { { name = "Digital Magazine" } } }) == "magazine")
assert(LoanModel.media_type({ type = { id = "audiobook" } }) == "audiobook")
assert(LoanModel.media_type({ type = { id = "magazine" } }) == "magazine")
assert(LoanModel.media_type({ formats = { { id = "ebook-kindle" } } }) == "ebook")
assert(LoanModel.non_adobe_format_label({ formats = { { id = "ebook-kindle" }, { id = "ebook-overdrive" }, { id = "ebook-kobo" } } }) == "Kindle / Libby App")
assert(LoanModel.non_adobe_format_label({ formats = { { id = "ebook-overdrive" } } }) == "Libby App")
assert(LoanModel.non_adobe_format_label({ formats = { { id = "ebook-kindle" } } }) == "Kindle")
assert(LoanModel.non_adobe_format_label({ formats = { { id = "ebook-kobo" } } }) == nil)

print("loan_media_type_test: ok")
