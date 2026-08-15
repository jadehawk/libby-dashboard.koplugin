local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local ltn12 = require("ltn12")
local rapidjson = require("rapidjson")
local https = require("ssl.https")
local _ = require("gettext")

local Updater = {}

local REPO = "jadehawk/libby-dashboard.koplugin"
local LATEST_URL = "https://api.github.com/repos/" .. REPO .. "/releases/latest"
local ASSET_NAME = "libby-dashboard.koplugin.zip"
local PLUGIN_DIR_NAME = "libby-dashboard.koplugin"
local RELEASE_DOWNLOAD_PREFIX = "https://github.com/" .. REPO .. "/releases/download/"

local function trustedReleaseUrl(value)
    return type(value) == "string"
        and value:sub(1, #RELEASE_DOWNLOAD_PREFIX) == RELEASE_DOWNLOAD_PREFIX
        and not value:find("[%c%s]")
end

local function safeArchivePath(value)
    if type(value) ~= "string" or value == "" or value:find("\0", 1, true) then return nil end
    local normalized = value:gsub("\\", "/")
    if normalized:sub(1, 1) == "/" or normalized:match("^%a:/") then return nil end
    local parts = {}
    for part in normalized:gmatch("[^/]+") do
        if part == ".." then return nil end
        if part ~= "." and part ~= "" then parts[#parts + 1] = part end
    end
    if #parts == 0 then return nil end
    return table.concat(parts, "/")
end

Updater._trustedReleaseUrl = trustedReleaseUrl
Updater._safeArchivePath = safeArchivePath

local function parseVersion(value)
    if type(value) ~= "string" then return nil end
    local major, minor, patch = value:match("^v?(%d+)%.(%d+)%.(%d+)$")
    if not major then return nil end
    return tonumber(major), tonumber(minor), tonumber(patch)
end

function Updater.isNewer(candidate, current)
    local a, b, c = parseVersion(candidate)
    local x, y, z = parseVersion(current)
    if not a or not x then return false end
    if a ~= x then return a > x end
    if b ~= y then return b > y end
    return c > z
end

local function request(url, sink)
    local ok, code, headers, status = https.request{
        url = url,
        method = "GET",
        headers = {
            ["Accept"] = "application/vnd.github+json",
            ["Accept-Encoding"] = "identity",
            ["User-Agent"] = "Libby-Dashboard-KOReader",
            ["X-GitHub-Api-Version"] = "2022-11-28",
        },
        sink = sink,
    }
    if not ok then return nil, tostring(code or status or "HTTPS request failed") end
    if tonumber(code) ~= 200 then return nil, "GitHub returned HTTP " .. tostring(code) end
    return true, headers
end

local function latestRelease()
    local chunks = {}
    local ok, err = request(LATEST_URL, ltn12.sink.table(chunks))
    if not ok then return nil, err end
    local decoded_ok, release = pcall(rapidjson.decode, table.concat(chunks))
    if not decoded_ok or type(release) ~= "table" then return nil, "Could not read GitHub release information" end
    local tag = release.tag_name
    if not parseVersion(tag) then return nil, "Latest GitHub release has an invalid version tag" end
    for _, asset in ipairs(release.assets or {}) do
        if asset.name == ASSET_NAME and type(asset.browser_download_url) == "string" then
            if not trustedReleaseUrl(asset.browser_download_url) then
                return nil, "Latest release contains an unexpected download URL"
            end
            return { version = tag:gsub("^v", ""), url = asset.browser_download_url }
        end
    end
    return nil, "Latest release does not contain " .. ASSET_NAME
end

local function sq(path)
    return "'" .. path:gsub("'", "'\\''") .. "'"
end

local function childNames(dir)
    local names = {}
    local ok, iterator, dir_obj = pcall(lfs.dir, dir)
    if not ok or not iterator then return names end
    for name in iterator, dir_obj do
        if name ~= "." and name ~= ".." then names[#names + 1] = name end
    end
    return names
end

local function prepareExtractedPlugin(raw_dir, staging)
    local packaged = raw_dir .. "/" .. PLUGIN_DIR_NAME
    if lfs.attributes(packaged .. "/main.lua", "mode") == "file"
        and lfs.attributes(packaged .. "/_meta.lua", "mode") == "file" then
        if not os.rename(packaged, staging) then return nil, "Could not prepare extracted update" end
        os.execute("rm -rf " .. sq(raw_dir))
        return true
    end

    if lfs.attributes(raw_dir .. "/main.lua", "mode") == "file"
        and lfs.attributes(raw_dir .. "/_meta.lua", "mode") == "file" then
        if not os.rename(raw_dir, staging) then return nil, "Could not prepare extracted update" end
        return true
    end

    local names = childNames(raw_dir)
    local root = names[1]
    if #names == 1 and root and lfs.attributes(raw_dir .. "/" .. root, "mode") == "directory"
        and lfs.attributes(raw_dir .. "/" .. root .. "/main.lua", "mode") == "file"
        and lfs.attributes(raw_dir .. "/" .. root .. "/_meta.lua", "mode") == "file" then
        if not os.rename(raw_dir .. "/" .. root, staging) then return nil, "Could not prepare extracted update" end
        os.execute("rm -rf " .. sq(raw_dir))
        return true
    end
    return nil, "Update archive does not contain a valid Libby Dashboard plugin"
end

local function unpack(zip_path, staging, raw_dir)
    os.execute("rm -rf " .. sq(raw_dir))
    if not lfs.mkdir(raw_dir) and lfs.attributes(raw_dir, "mode") ~= "directory" then
        return nil, "Could not create update staging directory"
    end

    local has_archiver, Archiver = pcall(require, "ffi/archiver")
    if has_archiver and type(Archiver) == "table" and Archiver.Reader then
        local arc = Archiver.Reader:new()
        if not arc:open(zip_path) then
            local err = arc.err
            arc:close()
            return nil, tostring(err or "Could not open update archive")
        end
        for entry in arc:iterate() do
            if entry.mode ~= "file" and entry.mode ~= "directory" then
                arc:close()
                os.execute("rm -rf " .. sq(raw_dir))
                return nil, "Update archive contains an unsupported entry type"
            end
            local normalized = safeArchivePath(entry.path)
            if not normalized then
                arc:close()
                os.execute("rm -rf " .. sq(raw_dir))
                return nil, "Update archive contains an unsafe path"
            end
            if not arc:extractToPath(entry.path, raw_dir .. "/" .. normalized) then break end
        end
        local err = arc.err
        arc:close()
        if err then return nil, tostring(err) end
        return prepareExtractedPlugin(raw_dir, staging)
    end

    if type(Device.unpackArchive) ~= "function" then return nil, "This KOReader build cannot extract update archives" end
    local ok, err = Device:unpackArchive(zip_path, raw_dir, true)
    if not ok then return nil, tostring(err or "Archive extraction failed") end
    return prepareExtractedPlugin(raw_dir, staging)
end

local function apply(plugin_dir, release)
    local dir = tostring(plugin_dir or ""):gsub("/+$", "")
    local parent = dir:match("^(.*)/[^/]+$")
    local name = dir:match("([^/]+)$")
    if not parent or not name then return nil, "Cannot determine plugin directory" end
    local zip_path = parent .. "/libby-dashboard-update.zip"
    local staging = parent .. "/" .. name .. ".update"
    local raw_dir = parent .. "/" .. name .. ".unpack"
    local backup = parent .. "/" .. name .. ".bak"
    os.execute("rm -rf " .. sq(staging) .. " " .. sq(raw_dir) .. " " .. sq(backup))
    local file, err = io.open(zip_path, "wb")
    if not file then return nil, tostring(err or "Could not create update file") end
    local ok, download_err = request(release.url, ltn12.sink.file(file))
    if not ok then os.remove(zip_path); return nil, download_err end
    local unpack_ok, unpack_err = unpack(zip_path, staging, raw_dir)
    os.remove(zip_path)
    if not unpack_ok then os.execute("rm -rf " .. sq(staging) .. " " .. sq(raw_dir)); return nil, unpack_err end
    if lfs.attributes(staging .. "/main.lua", "mode") ~= "file" or lfs.attributes(staging .. "/_meta.lua", "mode") ~= "file" then
        os.execute("rm -rf " .. sq(staging))
        return nil, "Update archive does not contain a valid Libby Dashboard plugin"
    end
    if not os.rename(dir, backup) then os.execute("rm -rf " .. sq(staging)); return nil, "Could not create plugin backup" end
    if not os.rename(staging, dir) then
        os.rename(backup, dir)
        os.execute("rm -rf " .. sq(staging))
        return nil, "Could not install updated plugin"
    end
    os.execute("rm -rf " .. sq(backup) .. " " .. sq(raw_dir))
    return true
end

function Updater.check(plugin, interactive)
    local wifi_on = type(NetworkMgr.isWifiOn) == "function" and NetworkMgr:isWifiOn()
    local connected = type(NetworkMgr.isConnected) == "function" and NetworkMgr:isConnected()
    if not (wifi_on and connected) then
        if interactive then UIManager:show(InfoMessage:new{ text = _("Wi-Fi must be on and connected to check for updates.") }) end
        return
    end
    local checking_message = InfoMessage:new{ text = _("Checking for Libby Dashboard updates...") }
    UIManager:show(checking_message)
    UIManager:forceRePaint()
    local release, err = latestRelease()
    UIManager:close(checking_message)
    UIManager:forceRePaint()
    if not release then
        UIManager:show(InfoMessage:new{ text = _("Could not check for updates:") .. "\n\n" .. tostring(err), timeout = 6 })
        return
    end
    if not Updater.isNewer(release.version, plugin.PLUGIN_VERSION) then
        UIManager:show(InfoMessage:new{ text = _("Libby Dashboard is up to date (v") .. plugin.PLUGIN_VERSION .. ").", timeout = 4 })
        return
    end
    UIManager:show(ConfirmBox:new{
        text = _("Libby Dashboard v") .. release.version .. _(" is available.\n\nInstalled: v") .. plugin.PLUGIN_VERSION .. _("\n\nDownload and install the update?"),
        ok_text = _("Update"),
        ok_callback = function()
            local updating_message = InfoMessage:new{ text = _("Downloading and installing Libby Dashboard update...") }
            UIManager:show(updating_message)
            UIManager:forceRePaint()
            local ok, apply_err = apply(plugin.path, release)
            UIManager:close(updating_message)
            UIManager:forceRePaint()
            if not ok then
                UIManager:show(InfoMessage:new{ text = _("Update failed:") .. "\n\n" .. tostring(apply_err), timeout = 6 })
                return
            end
            UIManager:show(ConfirmBox:new{
                text = _("Libby Dashboard v") .. release.version .. _(" installed. KOReader must restart to use the update."),
                ok_text = _("Restart now"),
                ok_callback = function() UIManager:quit(UIManager.RETURN_CODE_REBOOT or 85) end,
                cancel_text = _("Later"),
            })
        end,
    })
end

return Updater
