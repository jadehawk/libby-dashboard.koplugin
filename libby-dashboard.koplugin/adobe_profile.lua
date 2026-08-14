local AdobeProfile = {}

AdobeProfile.VERSION = 1

local REQUIRED_FIELDS = {
    "deviceKey",
    "privateLicenseKey",
    "user",
    "pkcs12",
    "deviceUUID",
    "fingerprint",
}

local OPTIONAL_FIELDS = {
    "licenseCert",
    "username",
    "authCert",
    "activationURL",
    "authorizationType",
    "signInMethod",
}

local function copy_fields(source)
    local result = {
        profileVersion = AdobeProfile.VERSION,
    }
    for _, key in ipairs(REQUIRED_FIELDS) do
        result[key] = source[key]
    end
    for _, key in ipairs(OPTIONAL_FIELDS) do
        result[key] = source[key]
    end
    return result
end

function AdobeProfile.validate(profile)
    if type(profile) ~= "table" then
        return nil, "Adobe registration profile is missing"
    end

    local version = profile.profileVersion or AdobeProfile.VERSION
    if version ~= AdobeProfile.VERSION then
        return nil, "Unsupported Adobe registration profile version: " .. tostring(version)
    end

    for _, key in ipairs(REQUIRED_FIELDS) do
        local value = profile[key]
        if type(value) ~= "string" or value == "" then
            return nil, "Adobe registration profile is missing " .. key
        end
    end

    return true
end

function AdobeProfile.normalize(profile)
    local ok, err = AdobeProfile.validate(profile)
    if not ok then
        return nil, err
    end
    return copy_fields(profile)
end

function AdobeProfile.from_activation_blob(blob)
    return AdobeProfile.normalize(blob)
end

function AdobeProfile.to_activation_blob(profile)
    return AdobeProfile.normalize(profile)
end

function AdobeProfile.should_adopt_external(profile)
    return AdobeProfile.validate(profile) ~= true
end

function AdobeProfile.summary(profile)
    local ok = AdobeProfile.validate(profile)
    if not ok then
        return {
            registered = false,
        }
    end

    return {
        registered = true,
        profileVersion = profile.profileVersion or AdobeProfile.VERSION,
        user = profile.user,
        username = profile.username,
        deviceUUID = profile.deviceUUID,
        activationURL = profile.activationURL,
        authorizationType = profile.authorizationType
            or ((profile.username and profile.username ~= "" and profile.username ~= "anonymous") and "account" or "anonymous"),
        signInMethod = profile.signInMethod,
    }
end

function AdobeProfile.reset(state)
    if type(state) ~= "table" then
        return false
    end
    local had_profile = state.adobe_registration ~= nil
    state.adobe_registration = nil
    return had_profile
end

return AdobeProfile
