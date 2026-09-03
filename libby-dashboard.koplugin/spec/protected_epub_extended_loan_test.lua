package.path = "./libby-dashboard.koplugin/?.lua;" .. package.path

local book_path = "/tmp/libby-extended-loan-test.epub"
local rights_path = book_path .. ".lic"
local rights = assert(io.open(rights_path, "wb"))
rights:write([[
<rights>
  <until>2000-01-01T00:00:00Z</until>
  <encryptedKey>test-encrypted-key</encryptedKey>
</rights>
]])
rights:close()

package.loaded["protected_epub"] = nil
package.loaded["adobe_profile"] = {
    normalize = function(value) return value end,
}
package.loaded["util"] = {
    pathExists = function(path) return path == rights_path end,
}
package.loaded["logger"] = {
    info = function() end,
    warn = function() end,
    err = function() end,
}
package.loaded["adobe.adobe"] = {
    restoreActivation = function(profile)
        assert(type(profile) == "table")
        return { creds = { licenseKey = "license-key" } }
    end,
}
package.loaded["adobe.fulfillment"] = {
    decryptBookKey = function(encrypted_key, license_key)
        assert(encrypted_key == "test-encrypted-key")
        assert(license_key == "license-key")
        return string.rep("K", 16)
    end,
}

local ProtectedEpub = require("protected_epub")

local normal_ok, normal_err = pcall(ProtectedEpub.resolve, book_path, {
    adobe_registration = {},
    extended_loan_time = false,
})
assert(normal_ok == false, "normal policy must reject an expired protected EPUB")
assert(tostring(normal_err):find("This library loan has expired", 1, true), tostring(normal_err))

local extended_key = ProtectedEpub.resolve(book_path, {
    adobe_registration = {},
    extended_loan_time = true,
})
assert(extended_key == string.rep("K", 16), "Extended Loan Time must allow the same unchanged expired rights file")

local reread = assert(io.open(rights_path, "rb"))
local after = reread:read("*a")
reread:close()
assert(after:find("<until>2000-01-01T00:00:00Z</until>", 1, true), "Extended Loan Time must not rewrite rights metadata")
os.remove(rights_path)

print("protected_epub_extended_loan_test: ok")
