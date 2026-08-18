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

print("loan_media_type_test: ok")
