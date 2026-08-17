package.path = "./libby-dashboard.koplugin/?.lua;./libby-dashboard.koplugin/dependencies/?.lua;./libby-dashboard.koplugin/dependencies/?/?.lua;" .. package.path

package.loaded["epub_metadata"] = nil
package.preload["ffi/archiver"] = function()
    return { Reader = {} }
end
package.preload["util"] = function()
    return { readFromFile = function() return nil end }
end
package.preload["adobe.util.util"] = function()
    return { orderedPairs = pairs }
end

local EpubMetadata = require("epub_metadata")
local parse = EpubMetadata._parseXmlMetadata
assert(type(parse) == "function")

local epub2 = [[
<package xmlns="http://www.idpf.org/2007/opf" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <metadata>
    <dc:title>The Test Book</dc:title>
    <dc:creator>Alice Example</dc:creator>
    <dc:creator>Bob Example</dc:creator>
    <meta name="calibre:series" content="Test Series"/>
    <meta name="calibre:series_index" content="2.5"/>
  </metadata>
</package>
]]
local metadata, err = parse(epub2)
assert(metadata, tostring(err))
assert(metadata.title == "The Test Book")
assert(metadata.author == "Alice Example")
assert(#metadata.authors == 2)
assert(metadata.authors[2].name == "Bob Example")
assert(metadata.series == "Test Series")
assert(metadata.series_index == "2.5")

local epub3 = [[
<package xmlns="http://www.idpf.org/2007/opf" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <metadata>
    <dc:title>Collection Book</dc:title>
    <dc:creator>Carol Writer</dc:creator>
    <meta property="belongs-to-collection" id="series-1">Modern Saga</meta>
    <meta refines="#series-1" property="collection-type">series</meta>
    <meta refines="#series-1" property="group-position">4</meta>
  </metadata>
</package>
]]
metadata, err = parse(epub3)
assert(metadata, tostring(err))
assert(metadata.series == "Modern Saga")
assert(metadata.series_index == "4")

local acsmStyle = [[
<adept:fulfillmentToken xmlns:adept="http://ns.adobe.com/adept" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <adept:resourceItemInfo>
    <adept:metadata>
      <dc:title>ACSM Metadata Title</dc:title>
      <dc:creator>Fallback Author</dc:creator>
    </adept:metadata>
  </adept:resourceItemInfo>
</adept:fulfillmentToken>
]]
metadata, err = parse(acsmStyle)
assert(metadata, tostring(err))
assert(metadata.title == "ACSM Metadata Title")
assert(metadata.author == "Fallback Author")

local merged = EpubMetadata.merge(
    { title = "EPUB Title", authors = {} },
    { title = "ACSM Title", author = "ACSM Author", authors = { { name = "ACSM Author" } }, library = "External ACSM" }
)
assert(merged.title == "EPUB Title")
assert(merged.author == "ACSM Author")
assert(merged.authors[1].name == "ACSM Author")
assert(merged.library == "External ACSM")

print("epub_metadata_test: ok")
