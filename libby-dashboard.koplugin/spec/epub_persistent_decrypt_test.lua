package.path = "./libby-dashboard.koplugin/?.lua;" .. package.path

local removed = {}
local closed = 0
local fakeStream = {}

package.loaded["adobe.epub"] = nil
package.preload["ffi"] = function()
    return {
        cdef = function() end,
        C = {
            fopen = function(path, mode)
                assert(path == "/books/test.epub")
                assert(mode == "wb")
                return fakeStream
            end,
            fileno = function(stream)
                assert(stream == fakeStream)
                return 77
            end,
            fclose = function(stream)
                assert(stream == fakeStream)
                closed = closed + 1
                return 0
            end,
            strerror = function() return "error" end,
        },
        gc = function(value) return value end,
        string = function(value) return tostring(value) end,
        errno = function() return 5 end,
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
    return {}
end
package.preload["adobe.util.zlib"] = function()
    return {}
end

local realRemove = os.remove
os.remove = function(path)
    removed[#removed + 1] = path
    return true
end

local epub = require("adobe.epub")

local captured
local successResult = { outputPath = "/books/test.epub", decryptedEntries = 4 }
epub.decryptAdobeEpubInMemory = function(inputPath, outputPath, bookKey, fd)
    captured = { inputPath, outputPath, bookKey, fd }
    return successResult
end

local result, err = epub.decryptAdobeEpub("/books/test.acsm.epub", "/books/test.epub", "0123456789abcdef")
assert(result == successResult, tostring(err))
assert(captured[1] == "/books/test.acsm.epub")
assert(captured[2] == "/books/test.epub")
assert(captured[3] == "0123456789abcdef")
assert(captured[4] == 77, "persistent decrypt must use the real output fd")
assert(closed == 1, "output stream must close after successful repack")
assert(#removed == 0, "successful output must not be removed")

-- A failed in-memory repack must close the fd and remove the partial plaintext file.
epub.decryptAdobeEpubInMemory = function()
    return nil, "repack failed"
end
local failed, failedErr = epub.decryptAdobeEpub("/books/test.acsm.epub", "/books/test.epub", "0123456789abcdef")
assert(failed == nil)
assert(failedErr == "repack failed")
assert(closed == 2)
assert(removed[#removed] == "/books/test.epub")

os.remove = realRemove
print("epub_persistent_decrypt_test: ok")
