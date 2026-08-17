package.path = "./libby-dashboard.koplugin/?.lua;" .. package.path

local decryptedOutput
local inflateInput

package.loaded["adobe.epub"] = nil
package.preload["ffi"] = function()
    return {
        cdef = function() end,
        C = {},
        gc = function(value) return value end,
        string = function(value, len)
            if type(value) == "string" then return value:sub(1, len) end
            return ""
        end,
    }
end
package.preload["ffi/archiver"] = function()
    return { Reader = {}, Writer = {} }
end
package.preload["datastorage"] = function()
    return { getDataDir = function() return "/tmp" end }
end
package.preload["libs/libkoreader-lfs"] = function()
    return { attributes = function() end }
end
package.preload["logger"] = function()
    return { info = function() end, warn = function() end }
end
package.preload["util"] = function()
    return {}
end
package.preload["adobe.util.dom"] = function()
    return {}
end
package.preload["ffi/posix_h"] = function()
    return true
end
package.preload["adobe.util.nativecrypto"] = function()
    return {
        aes_cbc_decrypt = function(key, iv, data, no_padding)
            assert(key == "0123456789abcdef")
            assert(iv == string.rep("\0", 16))
            assert(#data % 16 == 0)
            assert(no_padding == true)
            return decryptedOutput
        end,
    }
end
package.preload["adobe.util.zlib"] = function()
    return {
        inflateRaw = function(data)
            inflateInput = data
            return "inflated:" .. data
        end,
    }
end

local epub = require("adobe.epub")
local decrypt = epub._decryptAdeptEntryMemory
assert(type(decrypt) == "function")

local prefix = string.rep("R", 16)
local payload = "compressed-member-data"
local pad = 16 - ((16 + #payload) % 16)
if pad == 0 then pad = 16 end
decryptedOutput = prefix .. payload .. string.rep(string.char(pad), pad)
local encryptedPlaceholder = string.rep("E", #decryptedOutput)

local result, err = decrypt(encryptedPlaceholder, "0123456789abcdef", false)
assert(result == "inflated:" .. payload, tostring(err))
assert(inflateInput == payload)

inflateInput = nil
local rawResult, rawErr = decrypt(encryptedPlaceholder, "0123456789abcdef", true)
assert(rawResult == payload, tostring(rawErr))
assert(inflateInput == nil)

-- Corrupted PKCS#7 must be rejected before any inflate attempt.
decryptedOutput = prefix .. payload .. string.rep(string.char(pad), pad - 1) .. "\0"
local invalid, invalidErr = decrypt(encryptedPlaceholder, "0123456789abcdef", false)
assert(invalid == nil)
assert(invalidErr == "Invalid PKCS#7 padding")

-- Encrypted ADEPT members are block-aligned and include prefix + padding.
local badLength, badLengthErr = decrypt("too short", "0123456789abcdef", false)
assert(badLength == nil)
assert(badLengthErr == "Invalid ADEPT encrypted member length")

print("epub_memory_decrypt_test: ok")
