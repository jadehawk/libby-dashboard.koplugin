local cjson = require("cjson")

local StateStore = {}
StateStore.__index = StateStore

local function dirname(path)
    return path:match("^(.*)[/\\][^/\\]+$")
end

local function ensure_dir(path)
    if not path or path == "" then
        return true
    end
    local command = string.format("mkdir -p %q", path)
    local ok = os.execute(command)
    return ok == true or ok == 0
end

function StateStore.new(path)
    assert(type(path) == "string" and path ~= "", "state path is required")
    return setmetatable({ path = path }, StateStore)
end

function StateStore:load()
    local file = io.open(self.path, "rb")
    if not file then
        return {}
    end

    local raw = file:read("*a")
    file:close()
    if raw == "" then
        return {}
    end

    local ok, decoded = pcall(cjson.decode, raw)
    if not ok or type(decoded) ~= "table" then
        return nil, "State file is not valid JSON"
    end
    return decoded
end

function StateStore:save(state)
    assert(type(state) == "table", "state must be a table")
    local parent = dirname(self.path)
    if parent and not ensure_dir(parent) then
        return nil, "Could not create state directory"
    end

    local ok, encoded = pcall(cjson.encode, state)
    if not ok then
        return nil, "Could not encode state"
    end

    local temp_path = self.path .. ".tmp"
    local file, err = io.open(temp_path, "wb")
    if not file then
        return nil, err or "Could not open temporary state file"
    end
    file:write(encoded)
    file:write("\n")
    file:close()

    local renamed, rename_err = os.rename(temp_path, self.path)
    if not renamed then
        os.remove(temp_path)
        return nil, rename_err or "Could not replace state file"
    end

    -- Best effort on POSIX/WSL. Failure does not make the state unusable.
    os.execute(string.format("chmod 600 %q >/dev/null 2>&1", self.path))
    return true
end

function StateStore:delete()
    local ok, err = os.remove(self.path)
    if ok then
        return true
    end
    local probe = io.open(self.path, "rb")
    if not probe then
        return true
    end
    probe:close()
    return nil, err or "Could not remove state file"
end

return StateStore
