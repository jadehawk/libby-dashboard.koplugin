package.path = "./libby-dashboard.koplugin/?.lua;" .. package.path

package.loaded["adobe.epub"] = nil

local output = {}
local seekedToZero = false

package.preload["ffi"] = function()
    return {
        cdef = function() end,
        errno = function() return 0 end,
        C = {
            write = function(fd, data, len)
                assert(fd == 98)
                output[#output + 1] = data:sub(1, len)
                return len
            end,
            lseek = function(fd, offset, whence)
                assert(fd == 98)
                assert(offset == 0)
                assert(whence == 0)
                seekedToZero = true
                return 0
            end,
        },
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
package.preload["util"] = function() return {} end
package.preload["adobe.util.dom"] = function() return {} end
package.preload["ffi/posix_h"] = function() return true end
package.preload["adobe.util.nativecrypto"] = function() return {} end
package.preload["adobe.util.zlib"] = function()
    return {
        crc32 = function(data)
            -- The ZIP writer only needs a 32-bit value from this dependency;
            -- CRC correctness is covered by the real emulator integration.
            return #data
        end,
    }
end

local epub = require("adobe.epub")
assert(type(epub._newMemoryZipWriter) == "function")

local writer, err = epub._newMemoryZipWriter(98)
assert(writer, tostring(err))
assert(writer:addFileFromMemory("mimetype", "application/epub+zip"))
assert(writer:addFileFromMemory("OPS/chapter.xhtml", "<p>Hello</p>"))
assert(writer:close())
assert(seekedToZero == true)

local bytes = table.concat(output)
assert(bytes:sub(1, 4) == "PK\003\004")
assert(bytes:find("mimetype", 1, true))
assert(bytes:find("OPS/chapter.xhtml", 1, true))
assert(bytes:sub(-22, -19) == "PK\005\006")

print("android_memfd_writer_test: ok")
