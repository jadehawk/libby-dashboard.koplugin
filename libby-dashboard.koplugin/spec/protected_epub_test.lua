package.path = "./libby-dashboard.koplugin/?.lua;" .. package.path

package.loaded["protected_epub"] = nil
package.preload["adobe_profile"] = function()
    return { normalize = function(value) return value end }
end
package.preload["util"] = function()
    return {
        pathExists = function(path)
            return path == "/books/protected.epub.rights"
        end,
        getFilesystemType = function(path)
            if path == "/dev/shm" then return "tmpfs" end
            return "ext4"
        end,
        directoryExists = function(path)
            return path == "/dev/shm"
        end,
        makePath = function() return true end,
    }
end
package.preload["datastorage"] = function()
    return {
        getSettingsDir = function() return "/tmp" end,
    }
end
package.preload["logger"] = function()
    return {
        info = function() end,
        warn = function() end,
        err = function() end,
    }
end

local ProtectedEpub = require("protected_epub")

assert(ProtectedEpub.isProtected("/books/protected.epub") == true)
assert(ProtectedEpub.isProtected("/books/plain.epub") == false)
assert(ProtectedEpub.isProtected("/books/protected.pdf") == false)

local fallbackCloseCalls = 0
package.loaded["ffi"] = nil
package.preload["ffi"] = function()
    local ffi = {
        arch = "arm",
        C = {},
        cdef = function() end,
        new = function()
            return { value = "" }
        end,
        copy = function(buffer, value)
            buffer.value = value:gsub("XXXXXX$", "ABC123")
        end,
        string = function(buffer)
            return buffer.value
        end,
    }
    ffi.C.mkstemp = function(buffer)
        assert(buffer.value == "/dev/shm/libby-protected-ABC123")
        return 9
    end
    ffi.C.unlink = function(path)
        assert(path == "/dev/shm/libby-protected-ABC123")
        return 0
    end
    ffi.C.close = function(fd)
        assert(fd == 9)
        fallbackCloseCalls = fallbackCloseCalls + 1
        return 0
    end
    return ffi
end

local fallback, fallbackErr = ProtectedEpub._createAnonymousFile(true)
assert(fallback, tostring(fallbackErr))
assert(fallback.path == "/proc/self/fd/9")
fallback:close()
assert(fallbackCloseCalls == 1)

local syscallCloseCalls = 0
package.loaded["ffi"] = nil
package.preload["ffi"] = function()
    local ffi = {
        arch = "arm64",
        C = {},
        cdef = function() end,
        cast = function(ctype, value)
            return { ctype = ctype, value = value }
        end,
    }
    ffi.C.memfd_create = function()
        error("memfd_create wrapper unavailable")
    end
    ffi.C.syscall = function(number, name, flags)
        assert(number == 279)
        assert(type(name) == "table" and name.ctype == "const char *" and name.value == "libby-protected-epub")
        assert(type(flags) == "table" and flags.ctype == "unsigned int" and flags.value == 1)
        return 11
    end
    ffi.C.close = function(fd)
        assert(fd == 11)
        syscallCloseCalls = syscallCloseCalls + 1
        return 0
    end
    return ffi
end

local syscallHandle, syscallErr = ProtectedEpub._createAnonymousFile(false)
assert(syscallHandle, tostring(syscallErr))
assert(syscallHandle.path == "/proc/self/fd/11")
syscallHandle:close()
assert(syscallCloseCalls == 1)

local prepared = 0
local closed = 0
local privateUnlinks = 0
ProtectedEpub.prepare = function(path, settings)
    prepared = prepared + 1
    assert(path == "/books/protected.epub")
    assert(settings.marker == "settings")
    return {
        path = "/private/libby-protected.epub",
        private_path = "/private/libby-protected.epub",
        unlinkPrivatePath = function(self)
            assert(self.private_path == "/private/libby-protected.epub")
            privateUnlinks = privateUnlinks + 1
            self.private_path = nil
        end,
        close = function(self)
            closed = closed + 1
        end,
    }
end

local originalLoads = 0
local originalCloses = 0
local cacheInitCalls = 0
local disabledCacheCalls = 0
local CreDocument = {}
function CreDocument.loadDocument(document, full_document)
    originalLoads = originalLoads + 1
    document._loaded = true
    return true
end
function CreDocument.close(document)
    originalCloses = originalCloses + 1
    document.is_open = false
    return "closed"
end
function CreDocument.cacheInit()
    cacheInitCalls = cacheInitCalls + 1
end

local fakeCre = {
    initCache = function(path, size, compress, storage_factor)
        disabledCacheCalls = disabledCacheCalls + 1
        assert(path == "")
        assert(size == 32 * 1024 * 1024)
        assert(compress == true)
        assert(storage_factor == 40)
    end,
}

ProtectedEpub.install(CreDocument, function()
    return { marker = "settings" }
end)

local nativePath
local nativeMetadataOnly
local protectedDoc = {
    file = "/books/protected.epub",
    _loaded = false,
    is_open = true,
    engineInit = function()
        return fakeCre
    end,
    _document = {
        loadDocument = function(_, path, metadata_only)
            nativePath = path
            nativeMetadataOnly = metadata_only
            return true
        end,
    },
}

assert(CreDocument.loadDocument(protectedDoc, true) == true)
assert(prepared == 1)
assert(originalLoads == 0)
assert(nativePath == "/private/libby-protected.epub")
assert(nativeMetadataOnly == false)
assert(protectedDoc.file == "/books/protected.epub")
assert(privateUnlinks == 1)
assert(disabledCacheCalls == 1)
assert(cacheInitCalls == 0)

protectedDoc._loaded = false
assert(CreDocument.loadDocument(protectedDoc, false) == true)
assert(prepared == 1)
assert(nativeMetadataOnly == true)

assert(CreDocument.close(protectedDoc) == "closed")
assert(originalCloses == 1)
assert(closed == 1)
assert(cacheInitCalls == 1)

local plainDoc = {
    file = "/books/plain.epub",
    _loaded = false,
    is_open = true,
    _document = { loadDocument = function() error("should not use protected loader") end },
}
assert(CreDocument.loadDocument(plainDoc, true) == true)
assert(originalLoads == 1)

print("protected_epub_test: ok")
