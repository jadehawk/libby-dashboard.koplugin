local ProtectedEpub = {}

local AdobeProfile = require("adobe_profile")
local koUtil = require("util")

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

function ProtectedEpub.resolve(path, settings)
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

return ProtectedEpub
