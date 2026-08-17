local bit = require("bit")
local rapidjson = require("rapidjson")
local nativecrypto = require("adobe.util.nativecrypto")
local util = require("adobe.util.util")

local AccountBackup = {}

AccountBackup.FORMAT = "libby-dashboard-account-backup"
AccountBackup.VERSION = 2
AccountBackup.LEGACY_ENCRYPTED_VERSION = 1
AccountBackup.KDF_ROUNDS = 100000
AccountBackup.MAX_LABEL_CHARS = 48
AccountBackup.MAX_FILENAME_LABEL_CHARS = 24

local function derive(password, salt, rounds)
    local material, err = nativecrypto.pbkdf2_sha256(password, salt, rounds, 48)
    if not material then return nil, nil, err end
    return material:sub(1, 16), material:sub(17, 48)
end

local function constant_time_equal(a, b)
    if type(a) ~= "string" or type(b) ~= "string" or #a ~= #b then return false end
    local diff = 0
    for i = 1, #a do diff = bit.bor(diff, bit.bxor(a:byte(i), b:byte(i))) end
    return diff == 0
end

local function utf8_length(value)
    local count = 0
    for i = 1, #value do
        local byte = value:byte(i)
        if byte < 128 or byte >= 192 then count = count + 1 end
    end
    return count
end

local function trim(value)
    if type(value) ~= "string" then return nil end
    value = value:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    if value == "" then return nil end
    return value
end

local function hex(value)
    return (value:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end

local function authenticated_data_v2(envelope, salt, iv, ciphertext)
    return table.concat({
        AccountBackup.FORMAT,
        tostring(AccountBackup.VERSION),
        tostring(envelope.label or ""),
        tostring(envelope.created_at or ""),
        tostring(envelope.backup_id or ""),
        tostring(envelope.encryption or ""),
        tostring(envelope.kdf or ""),
        tostring(envelope.rounds or ""),
        salt,
        iv,
        ciphertext,
    }, "\0")
end

function AccountBackup.validate_label(label)
    label = trim(label)
    if not label then return nil, "Backup name is required" end
    if utf8_length(label) > AccountBackup.MAX_LABEL_CHARS then
        return nil, "Backup name must be " .. AccountBackup.MAX_LABEL_CHARS .. " characters or fewer"
    end
    return label
end

function AccountBackup.filename_slug(label)
    label = (trim(label) or "backup"):gsub("'", "")
    local slug = label:gsub("[^%w]+", "-"):gsub("^-+", ""):gsub("-+$", ""):lower()
    if slug == "" then slug = "backup" end
    if #slug > AccountBackup.MAX_FILENAME_LABEL_CHARS then
        slug = slug:sub(1, AccountBackup.MAX_FILENAME_LABEL_CHARS):gsub("-+$", "")
    end
    return slug ~= "" and slug or "backup"
end

function AccountBackup.create_metadata(label, created_at)
    local normalized, label_err = AccountBackup.validate_label(label)
    if not normalized then return nil, label_err end
    local random, random_err = nativecrypto.rand_bytes(8)
    if not random then return nil, random_err end
    return {
        label = normalized,
        created_at = created_at or os.date("!%Y-%m-%dT%H:%M:%SZ"),
        backup_id = hex(random),
    }
end

function AccountBackup.filename(metadata)
    if type(metadata) ~= "table" then return nil, "Backup metadata is invalid" end
    local label, label_err = AccountBackup.validate_label(metadata.label)
    if not label then return nil, label_err end
    local stamp = tostring(metadata.created_at or ""):gsub("[^0-9]", "")
    stamp = stamp:sub(1, 14)
    if #stamp < 8 then stamp = os.date("!%Y%m%d%H%M%S") end
    return "libby-dashboard-account-backup-" .. AccountBackup.filename_slug(label) .. "-" .. stamp .. ".json"
end

function AccountBackup.inspect(contents)
    local ok, envelope = pcall(rapidjson.decode, contents)
    if not ok or type(envelope) ~= "table" or envelope.format ~= AccountBackup.FORMAT then return nil end
    if envelope.version == AccountBackup.LEGACY_ENCRYPTED_VERSION then
        return { version = envelope.version }
    end
    if envelope.version ~= AccountBackup.VERSION then return nil end
    local label = AccountBackup.validate_label(envelope.label)
    if not label or type(envelope.created_at) ~= "string" or envelope.created_at == ""
        or type(envelope.backup_id) ~= "string" or envelope.backup_id == "" then return nil end
    return {
        version = envelope.version,
        label = label,
        created_at = envelope.created_at,
        backup_id = envelope.backup_id,
    }
end

function AccountBackup.encode(payload, password, metadata)
    if type(password) ~= "string" or #password < 8 then return nil, "Backup password must be at least 8 characters" end
    if type(metadata) ~= "table" then return nil, "Backup metadata is required" end
    local label, label_err = AccountBackup.validate_label(metadata.label)
    if not label then return nil, label_err end
    if type(metadata.created_at) ~= "string" or metadata.created_at == "" or type(metadata.backup_id) ~= "string" or metadata.backup_id == "" then
        return nil, "Backup metadata is invalid"
    end
    local ok, plaintext = pcall(rapidjson.encode, payload)
    if not ok then return nil, "Could not encode account backup" end
    local salt, salt_err = nativecrypto.rand_bytes(16)
    if not salt then return nil, salt_err end
    local iv, iv_err = nativecrypto.rand_bytes(16)
    if not iv then return nil, iv_err end
    local enc_key, mac_key, derive_err = derive(password, salt, AccountBackup.KDF_ROUNDS)
    if not enc_key then return nil, derive_err end
    local ciphertext, enc_err = nativecrypto.aes_cbc_encrypt(enc_key, iv, plaintext, false)
    if not ciphertext then return nil, enc_err end
    local envelope = {
        format = AccountBackup.FORMAT,
        version = AccountBackup.VERSION,
        label = label,
        created_at = metadata.created_at,
        backup_id = metadata.backup_id,
        encryption = "AES-128-CBC+HMAC-SHA256",
        kdf = "PBKDF2-HMAC-SHA256",
        rounds = AccountBackup.KDF_ROUNDS,
    }
    local mac, mac_err = nativecrypto.hmac_sha256(mac_key, authenticated_data_v2(envelope, salt, iv, ciphertext))
    if not mac then return nil, mac_err end
    envelope.salt = util.base64.encode(salt)
    envelope.iv = util.base64.encode(iv)
    envelope.ciphertext = util.base64.encode(ciphertext)
    envelope.mac = util.base64.encode(mac)
    return rapidjson.encode(envelope)
end

function AccountBackup.decode(contents, password)
    local ok, envelope = pcall(rapidjson.decode, contents)
    if not ok or type(envelope) ~= "table" or envelope.format ~= AccountBackup.FORMAT then
        return nil, "Account backup file is invalid"
    end
    if envelope.version ~= AccountBackup.VERSION and envelope.version ~= AccountBackup.LEGACY_ENCRYPTED_VERSION then
        return nil, "Unsupported account backup version"
    end
    local rounds = tonumber(envelope.rounds)
    if envelope.kdf ~= "PBKDF2-HMAC-SHA256" or not rounds or rounds < 10000 or rounds > 1000000 then
        return nil, "Account backup KDF parameters are invalid"
    end
    local decode_ok, salt, iv, ciphertext, mac = pcall(function()
        return util.base64.decode(envelope.salt), util.base64.decode(envelope.iv),
            util.base64.decode(envelope.ciphertext), util.base64.decode(envelope.mac)
    end)
    if not decode_ok or not salt or not iv or not ciphertext or not mac then return nil, "Account backup encoding is invalid" end
    local enc_key, mac_key, derive_err = derive(password or "", salt, rounds)
    if not enc_key then return nil, derive_err end
    local mac_input = envelope.version == AccountBackup.VERSION
        and authenticated_data_v2(envelope, salt, iv, ciphertext)
        or (salt .. iv .. ciphertext)
    local expected_mac, mac_err = nativecrypto.hmac_sha256(mac_key, mac_input)
    if not expected_mac then return nil, mac_err end
    if not constant_time_equal(mac, expected_mac) then return nil, "Incorrect password or damaged account backup" end
    local plaintext, dec_err = nativecrypto.aes_cbc_decrypt(enc_key, iv, ciphertext, false)
    if not plaintext then return nil, dec_err end
    local json_ok, payload = pcall(rapidjson.decode, plaintext)
    if not json_ok or type(payload) ~= "table" then return nil, "Decrypted account backup is invalid" end
    if envelope.version == AccountBackup.VERSION then
        local backup = payload.backup
        if type(backup) ~= "table" or backup.label ~= envelope.label or backup.created_at ~= envelope.created_at or backup.backup_id ~= envelope.backup_id then
            return nil, "Account backup metadata validation failed"
        end
    end
    return payload
end

return AccountBackup
