local ProtectedEpub = {}

local AdobeProfile = require("adobe_profile")
local koUtil = require("util")
local logger = require("logger")

local function trace(level, ...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    local message = table.concat(parts, " ")
    if logger[level] then logger[level]("[Libby Protected]", message) end
end


local activePrivatePaths = {}

local function cleanupStaleAndroidPrivateFiles(androidDir)
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if not ok or not lfs or type(lfs.dir) ~= "function" then return end
    local iterOk, iter, dirState = pcall(lfs.dir, androidDir)
    if not iterOk or not iter then return end
    for name in iter, dirState do
        if name:match("^libby%-protected%-.*%.epub$") then
            local full = androidDir .. "/" .. name
            if not activePrivatePaths[full] then
                os.remove(full)
            end
        end
    end
end

local function stageAndroidPrivateFile(handle)
    local isAndroid, android = pcall(require, "android")
    if not isAndroid or not android or type(android.dir) ~= "string" then
        return true
    end

    cleanupStaleAndroidPrivateFiles(android.dir)
    local privatePath = android.dir .. "/libby-protected-" .. tostring(handle.fd) .. "-" .. tostring(os.time()) .. ".epub"
    os.remove(privatePath)

    local out, openErr = io.open(privatePath, "wb")
    if not out then return nil, "Could not create Android private EPUB: " .. tostring(openErr) end

    local ffi = require("ffi")
    pcall(ffi.cdef, [[
        ssize_t pread(int fd, void *buf, size_t count, off_t offset);
    ]])
    local chunkSize = 65536
    local buffer = ffi.new("uint8_t[?]", chunkSize)
    local offset = 0
    while true do
        local n = ffi.C.pread(handle.fd, buffer, chunkSize, offset)
        if n < 0 then
            local err = ffi.errno()
            out:close()
            os.remove(privatePath)
            return nil, "Could not read RAM EPUB for Android staging: errno=" .. tostring(err)
        end
        if n == 0 then break end
        local data = ffi.string(buffer, tonumber(n))
        local okWrite, writeErr = out:write(data)
        if not okWrite then
            out:close()
            os.remove(privatePath)
            return nil, "Could not write Android private EPUB: " .. tostring(writeErr)
        end
        offset = offset + tonumber(n)
    end
    out:flush()
    out:close()

    local probe = io.open(privatePath, "rb")
    local signature = probe and probe:read(4) or nil
    if probe then probe:close() end
    if signature ~= "PK" then
        os.remove(privatePath)
        return nil, "Android private EPUB staging validation failed"
    end

    handle.private_path = privatePath
    handle.path = privatePath
    activePrivatePaths[privatePath] = true
    trace("info", "android private staging ready:", privatePath, " bytes=", offset)
    return true
end

local function readFile(path)
    local file, err = io.open(path, "rb")
    if not file then return nil, err end
    local data = file:read("*a")
    file:close()
    return data
end

local function xmlText(xml, localName)
    return xml:match("<[%w_%-]+:" .. localName .. "[^>]*>%s*(.-)%s*</[%w_%-]+:" .. localName .. ">")
        or xml:match("<" .. localName .. "[^>]*>%s*(.-)%s*</" .. localName .. ">")
end

local function normalizeIsoUtc(value)
    if type(value) ~= "string" then return nil end
    local base = value:match("^(%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d)")
    if not base then return nil end
    return base .. "Z"
end

local function resolveBookKey(path, settings)
    if type(path) ~= "string" or not path:lower():match("%.epub$") then return nil end
    local rightsPath = path .. ".rights"
    if not koUtil.pathExists(rightsPath) then return nil end

    local rights, readErr = readFile(rightsPath)
    if not rights then error("Could not read ADEPT rights: " .. tostring(readErr)) end

    local untilValue = normalizeIsoUtc(xmlText(rights, "until"))
    if untilValue and os.date("!%Y-%m-%dT%H:%M:%SZ") > untilValue then
        error("This library loan has expired")
    end

    local encryptedKey = xmlText(rights, "encryptedKey")
    if not encryptedKey or encryptedKey == "" then error("ADEPT rights do not contain an encrypted book key") end

    local profile, profileErr = AdobeProfile.normalize(settings.adobe_registration)
    if not profile then error(profileErr) end
    local adobe = require("adobe.adobe")
    local restored, restoreErr = adobe.restoreActivation(profile)
    if not restored then error(restoreErr) end

    local fulfillment = require("adobe.fulfillment")
    local bookKey, keyErr = fulfillment.decryptBookKey(encryptedKey, restored.creds.licenseKey)
    if not bookKey then error(keyErr) end
    if #bookKey ~= 16 then error("ADEPT book key is not 16 bytes") end
    return bookKey
end

local function createMemfd(forceFallback)
    local ffi = require("ffi")
    pcall(ffi.cdef, [[
        int memfd_create(const char *name, unsigned int flags);
        long syscall(long number, ...);
        int mkstemp(char *template_name);
        int unlink(const char *pathname);
        int close(int fd);
    ]])

    local fd
    local ok, value = false, nil
    if not forceFallback then
        ok, value = pcall(function()
            return ffi.C.memfd_create("libby-protected-epub", 1)
        end)
    end
    if ok and value ~= nil and value >= 0 then
        fd = tonumber(value)
        trace("info", "anonymous backend: libc memfd fd=", fd)
    elseif not forceFallback then
        -- Some Android/embedded libc builds expose the kernel syscall but not
        -- the memfd_create() wrapper. These are Linux syscall numbers.
        local syscallNumber = {
            x86 = 356,
            x64 = 319,
            arm = 385,
            arm64 = 279,
        }
        local nr = syscallNumber[ffi.arch]
        if nr then
            local syscallOk, syscallFd = pcall(function()
                -- syscall() is variadic. LuaJIT passes plain Lua numbers as
                -- doubles in varargs, so force integer cdata for the flags
                -- argument or Linux will read the wrong register/value.
                local name = ffi.cast("const char *", "libby-protected-epub")
                local flags = ffi.cast("unsigned int", 1)
                return ffi.C.syscall(nr, name, flags)
            end)
            if syscallOk and syscallFd ~= nil and syscallFd >= 0 then
                fd = tonumber(syscallFd)
                trace("info", "anonymous backend: raw syscall memfd fd=", fd, " arch=", tostring(ffi.arch))
            else
                trace("warn", "raw syscall memfd failed arch=", tostring(ffi.arch), " result=", tostring(syscallFd))
            end
        end
    end

    if not fd then
        -- Older Linux kernels may not support memfd_create. Fall back only to
        -- a filesystem that the running device reports as RAM-backed, then
        -- unlink the name immediately while keeping its descriptor alive.
        local candidates = { "/dev/shm", "/tmp", "/var/tmp" }
        for _, dir in ipairs(candidates) do
            local fsType = koUtil.getFilesystemType and koUtil.getFilesystemType(dir) or nil
            if (fsType == "tmpfs" or fsType == "ramfs") and koUtil.directoryExists(dir) then
                local template = dir .. "/libby-protected-XXXXXX"
                local buffer = ffi.new("char[?]", #template + 1)
                ffi.copy(buffer, template)
                local fallbackFd = ffi.C.mkstemp(buffer)
                if fallbackFd >= 0 then
                    local pathname = ffi.string(buffer)
                    if ffi.C.unlink(pathname) == 0 then
                        fd = tonumber(fallbackFd)
                        trace("info", "anonymous backend: verified RAM filesystem fd=", fd, " path=", dir, " fs=", fsType)
                        break
                    end
                    ffi.C.close(fallbackFd)
                end
            end
        end
    end

    if not fd then
        trace("err", "anonymous backend unavailable: no memfd and no verified RAM filesystem")
        return nil, "No safe RAM-backed anonymous file is available on this platform"
    end

    local procPath = "/proc/self/fd/" .. tostring(fd)
    local handle = {
        fd = fd,
        path = procPath,
        proc_path = procPath,
        private_path = nil,
        closed = false,
    }
    function handle:unlinkPrivatePath()
        if self.private_path then
            activePrivatePaths[self.private_path] = nil
            ffi.C.unlink(self.private_path)
            trace("info", "android private staging unlinked:", self.private_path)
            self.private_path = nil
        end
    end
    function handle:close()
        if not self.closed then
            self:unlinkPrivatePath()
            ffi.C.close(self.fd)
            self.closed = true
        end
    end
    return handle
end

function ProtectedEpub.isProtected(path)
    return type(path) == "string"
        and path:lower():match("%.epub$") ~= nil
        and koUtil.pathExists(path .. ".rights")
end

function ProtectedEpub.prepare(path, settings)
    if not ProtectedEpub.isProtected(path) then return nil end

    trace("info", "prepare start:", path)
    local bookKey = resolveBookKey(path, settings)
    trace("info", "rights/key resolved")
    local handle, handleErr = createMemfd()
    if not handle then
        trace("err", "anonymous file creation failed:", handleErr)
        error(handleErr)
    end

    trace("info", "anonymous path ready:", handle.path)
    local epub = require("adobe.epub")
    trace("info", "in-memory EPUB repack start")
    local result, decryptErr = epub.decryptAdobeEpubInMemory(path, handle.path, bookKey, handle.fd, trace)
    bookKey = nil

    if not result then
        trace("err", "in-memory EPUB repack failed:", decryptErr)
        handle:close()
        error("Could not prepare protected EPUB in memory: " .. tostring(decryptErr))
    end
    trace("info", "in-memory EPUB repack complete")

    local ffi = require("ffi")
    pcall(ffi.cdef, [[
        ssize_t pread(int fd, void *buf, size_t count, off_t offset);
    ]])
    local sigbuf = ffi.new("uint8_t[4]")
    local readCount = ffi.C.pread(handle.fd, sigbuf, 4, 0)
    local signature = readCount == 4 and ffi.string(sigbuf, 4) or nil
    if signature ~= "PK" then
        trace("err", "memory EPUB ZIP validation failed; signature=", tostring(signature), " read=", tostring(readCount), " errno=", tostring(ffi.errno()))
        handle:close()
        error("Protected EPUB memory image is not a valid ZIP container")
    end

    trace("info", "memory EPUB validated")


    local staged, stageErr = stageAndroidPrivateFile(handle)
    if not staged then
        trace("err", "android private staging failed:", stageErr)
        handle:close()
        error(stageErr)
    end
    return handle
end

function ProtectedEpub.install(CreDocument, getSettings)
    CreDocument._libby_protected_epub_settings = getSettings
    if CreDocument._libby_protected_epub_hook then return end

    local originalLoadDocument = CreDocument.loadDocument
    local originalClose = CreDocument.close
    local handles = setmetatable({}, { __mode = "k" })
    local protectedCacheUsers = 0

    local function disableDiskCache(document)
        if protectedCacheUsers == 0 then
            local cre = document:engineInit()
            local compress = true
            local storageFactor = 40
            if G_reader_settings then
                compress = G_reader_settings:nilOrTrue("cre_compress_cached_data")
                storageFactor = G_reader_settings:readSetting("cre_storage_size_factor") or storageFactor
            end
            -- Stock KOReader documents this as "empty path = no cache".
            trace("info", "disabling crengine disk cache")
            cre.initCache("", 32 * 1024 * 1024, compress, storageFactor)
            trace("info", "crengine disk cache disabled")
        end
        protectedCacheUsers = protectedCacheUsers + 1
    end

    local function restoreDiskCache()
        if protectedCacheUsers <= 0 then return end
        protectedCacheUsers = protectedCacheUsers - 1
        if protectedCacheUsers == 0 then
            CreDocument.cacheInit()
        end
    end

    CreDocument.loadDocument = function(document, full_document)
        if not document._loaded and ProtectedEpub.isProtected(document.file) then
            local state = handles[document]
            if not state then
                local settingsProvider = CreDocument._libby_protected_epub_settings
                local settings = settingsProvider and settingsProvider() or nil
                if not settings then error("Libby Dashboard settings are unavailable") end
                local handle = ProtectedEpub.prepare(document.file, settings)
                disableDiskCache(document)
                state = { handle = handle, cache_disabled = true }
                handles[document] = state
            end

            local only_metadata = full_document == false
            trace("info", "crengine load start path=", state.handle.path, " metadata_only=", tostring(only_metadata))
            if document._document:loadDocument(state.handle.path, only_metadata) then
                document._loaded = true
                trace("info", "crengine load succeeded")
                if state.handle.private_path then
                    state.handle:unlinkPrivatePath()
                end
            elseif state.cache_disabled then
                trace("err", "crengine load returned false")
                state.handle:close()
                handles[document] = nil
                restoreDiskCache()
            end
            return document._loaded
        end
        return originalLoadDocument(document, full_document)
    end

    CreDocument.close = function(document)
        local state = handles[document]
        local result = originalClose(document)
        if state and document.is_open == false then
            state.handle:close()
            handles[document] = nil
            if state.cache_disabled then
                restoreDiskCache()
            end
        end
        return result
    end

    CreDocument._libby_protected_epub_hook = true
end

-- Compatibility aliases retained for callers/tests and portability probes.
ProtectedEpub.resolve = resolveBookKey
ProtectedEpub._createAnonymousFile = createMemfd

return ProtectedEpub
