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

local magazine = LoanModel.from_loan({
    id = "mag-issue-1",
    cardId = "card-1",
    title = "Vogue",
    type = { id = "magazine" },
    edition = "October 2026",
    parentMagazineTitleId = "vogue-parent",
    frequency = "Monthly",
    publishDate = "2026-10-01",
    covers = {
        cover300Wide = { href = "https://img.example.invalid/vogue-300.jpg" },
    },
}, {})
assert(magazine.media_type == "magazine")
assert(magazine.edition == "October 2026")
assert(magazine.parent_magazine_title_id == "vogue-parent")
assert(magazine.magazine_frequency == "Monthly")
assert(magazine.publish_date == "2026-10-01")
assert(magazine.cover_url == "https://img.example.invalid/vogue-300.jpg",
    "Thunder magazine cover metadata must normalize into cover_url")

print("loan_media_type_test: ok")
