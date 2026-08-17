package.path = "libby-dashboard.koplugin/?.lua;libby-dashboard.koplugin/?/init.lua;" .. package.path

package.loaded.bit = {
    bxor = function(a, b)
        local r, p = 0, 1
        while a > 0 or b > 0 do
            local aa, bb = a % 2, b % 2
            if aa ~= bb then r = r + p end
            a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
        end
        return r
    end,
    bor = function(a, b) return a + b - (a % 2 == 1 and b % 2 == 1 and 1 or 0) end,
}

local json_store, json_id = {}, 0
package.loaded.rapidjson = {
    encode = function(value)
        json_id = json_id + 1
        local key = "JSON:" .. json_id
        json_store[key] = value
        return key
    end,
    decode = function(value) return json_store[value] end,
}
package.loaded["adobe.util.util"] = {
    base64 = { encode = function(s) return s end, decode = function(s) return s end },
}
local function material(password, salt, length)
    local seed = password .. ":" .. salt
    local out = {}
    for i = 1, length do out[i] = string.char((seed:byte(((i - 1) % #seed) + 1) + i) % 256) end
    return table.concat(out)
end
local function mac(key, data)
    local sum = 0
    for i = 1, #key do sum = (sum + key:byte(i) * i) % 256 end
    for i = 1, #data do sum = (sum + data:byte(i) * (i + 7)) % 256 end
    return string.rep(string.char(sum), 32)
end
package.loaded["adobe.util.nativecrypto"] = {
    rand_bytes = function(n) return string.rep("R", n) end,
    pbkdf2_sha256 = function(password, salt, _, length) return material(password, salt, length) end,
    hmac_sha256 = mac,
    aes_cbc_encrypt = function(_, _, data) return "ENC" .. data end,
    aes_cbc_decrypt = function(_, _, data)
        if data:sub(1, 3) ~= "ENC" then return nil, "bad ciphertext" end
        return data:sub(4)
    end,
}

local AccountBackup = require("account_backup")
local metadata = assert(AccountBackup.create_metadata("Jimmy's Kindle", "2026-08-17T15:30:42Z"))
assert(metadata.label == "Jimmy's Kindle")
assert(#metadata.backup_id == 16)
assert(AccountBackup.filename_slug("Jimmy's Kindle With An Extremely Long Device Name") == "jimmys-kindle-with-an-ex")
assert(AccountBackup.filename(metadata) == "libby-dashboard-account-backup-jimmys-kindle-20260817153042.json")
assert(AccountBackup.validate_label(string.rep("a", 48)))
assert(AccountBackup.validate_label(string.rep("a", 49)) == nil)

local payload = {
    format = "libby-dashboard-account-data",
    version = 1,
    backup = metadata,
    libby = { identity = "libby-token" },
    adobe = { registration = { user = "adept-user" } },
}

local encoded, err = AccountBackup.encode(payload, "correct horse", metadata)
assert(encoded, err)
assert(not encoded:find("libby%-token"))
assert(not encoded:find("adept%-user"))
local inspected = assert(AccountBackup.inspect(encoded))
assert(inspected.version == 2)
assert(inspected.label == "Jimmy's Kindle")
assert(inspected.created_at == "2026-08-17T15:30:42Z")
assert(inspected.backup_id == metadata.backup_id)
local decoded, decode_err = AccountBackup.decode(encoded, "correct horse")
assert(decoded, decode_err)
assert(decoded.libby.identity == "libby-token")
assert(decoded.adobe.registration.user == "adept-user")
local wrong, wrong_err = AccountBackup.decode(encoded, "wrong password")
assert(wrong == nil)
assert(type(wrong_err) == "string" and wrong_err:find("Incorrect password"))
assert(AccountBackup.encode(payload, "short", metadata) == nil)

-- Visible v2 metadata is authenticated: changing the label must invalidate the file.
local original_envelope = json_store[encoded]
local tampered = {}
for key, value in pairs(original_envelope) do tampered[key] = value end
tampered.label = "Karen's Boox"
local tampered_encoded = package.loaded.rapidjson.encode(tampered)
local tampered_payload, tampered_err = AccountBackup.decode(tampered_encoded, "correct horse")
assert(tampered_payload == nil)
assert(type(tampered_err) == "string" and tampered_err:find("Incorrect password"))

-- Existing encrypted v1 backups remain importable.
local v1_plaintext = package.loaded.rapidjson.encode({
    format = "libby-dashboard-account-data",
    version = 1,
    libby = { identity = "legacy-encrypted-token" },
})
local salt, iv = string.rep("S", 16), string.rep("I", 16)
local enc_key, mac_key = material("legacy pass", salt, 48):sub(1, 16), material("legacy pass", salt, 48):sub(17, 48)
local ciphertext = "ENC" .. v1_plaintext
local v1_envelope = {
    format = AccountBackup.FORMAT,
    version = 1,
    encryption = "AES-128-CBC+HMAC-SHA256",
    kdf = "PBKDF2-HMAC-SHA256",
    rounds = AccountBackup.KDF_ROUNDS,
    salt = salt,
    iv = iv,
    ciphertext = ciphertext,
    mac = mac(mac_key, salt .. iv .. ciphertext),
}
local v1_encoded = package.loaded.rapidjson.encode(v1_envelope)
local v1_inspected = assert(AccountBackup.inspect(v1_encoded))
assert(v1_inspected.version == 1 and v1_inspected.label == nil)
local v1_decoded, v1_err = AccountBackup.decode(v1_encoded, "legacy pass")
assert(v1_decoded, v1_err)
assert(v1_decoded.libby.identity == "legacy-encrypted-token")

print("account_backup_test: ok")
