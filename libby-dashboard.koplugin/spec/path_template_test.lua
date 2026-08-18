package.path = "./libby-dashboard.koplugin/?.lua;" .. package.path

package.loaded["path_template"] = nil
local PathTemplate = require("path_template")

local template = "{home}/Libby_Loans/{author:first}/{series}/{series_index} - {title}.{ext}"
local options = { home = "/books", ext = "epub" }

local function resolve(model)
    return PathTemplate.resolve(template, model, options)
end

assert(resolve({
    author = "Example Author",
    title = "First Book",
    series = "Example Series",
    series_index = 1,
}) == "/books/Libby_Loans/Example Author/Example Series/01.00 - First Book.epub")

assert(resolve({
    author = "Example Author",
    title = "Half Book",
    series = "Example Series",
    series_index = ".5",
}) == "/books/Libby_Loans/Example Author/Example Series/00.50 - Half Book.epub")

assert(resolve({
    author = "Example Author",
    title = "Later Book",
    series = "Example Series",
    series_index = 12,
}) == "/books/Libby_Loans/Example Author/Example Series/12.00 - Later Book.epub")

assert(resolve({
    author = "Example Author",
    title = "Series Without Index",
    series = "Example Series",
}) == "/books/Libby_Loans/Example Author/Example Series/Series Without Index.epub")

assert(resolve({
    author = "Example Author",
    title = "Standalone",
}) == "/books/Libby_Loans/Example Author/Standalone.epub")

assert(resolve({
    author = "Example Author",
    title = "Standalone With Stray Index",
    series_index = 3,
}) == "/books/Libby_Loans/Example Author/Standalone With Stray Index.epub")

assert(not resolve({
    author = "Example Author",
    title = "Standalone",
}):find("No Series", 1, true))

print("path_template_test: ok")
