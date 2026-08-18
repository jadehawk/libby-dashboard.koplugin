local koUtil = require("util")

local ExternalAcsm = {}

local function exists(path, path_exists)
    path_exists = path_exists or koUtil.pathExists
    return path_exists(path) == true
end

function ExternalAcsm.pathOccupied(path, path_exists)
    return exists(path, path_exists)
        or exists(path .. ".lic", path_exists)
        or exists(path .. ".rights", path_exists)
end

function ExternalAcsm.stagingPath(target, path_exists)
    local stem, ext = target:match("^(.*)(%.[^./]+)$")
    stem = stem or target
    ext = ext or ""
    for index = 1, 999 do
        local candidate = stem .. ".libby-dashboard-replacement-" .. tostring(index) .. ext
        if not ExternalAcsm.pathOccupied(candidate, path_exists) then
            return candidate
        end
    end
    return nil, "Could not create a temporary replacement filename"
end

local function members(path)
    return { path, path .. ".lic", path .. ".rights" }
end

function ExternalAcsm.cleanup(path, path_exists, remove_file)
    path_exists = path_exists or koUtil.pathExists
    remove_file = remove_file or os.remove
    for _, candidate in ipairs(members(path)) do
        if path_exists(candidate) then remove_file(candidate) end
    end
end

function ExternalAcsm.replace(staging, target, path_exists, rename_file, remove_file)
    path_exists = path_exists or koUtil.pathExists
    rename_file = rename_file or os.rename
    remove_file = remove_file or os.remove

    local staging_members = members(staging)
    local target_members = members(target)
    if not path_exists(staging_members[1]) then
        return nil, "Replacement book was not prepared"
    end

    local backups = {}
    local backup_suffix = ".libby-dashboard-overwrite-backup"

    local function rollback()
        for _, final in ipairs(target_members) do
            if path_exists(final) then remove_file(final) end
        end
        for index = #backups, 1, -1 do
            local item = backups[index]
            if path_exists(item.backup) then rename_file(item.backup, item.target) end
        end
    end

    for _, target_member in ipairs(target_members) do
        if path_exists(target_member) then
            local backup = target_member .. backup_suffix
            if path_exists(backup) then remove_file(backup) end
            local ok, err = rename_file(target_member, backup)
            if not ok then
                rollback()
                return nil, "Could not preserve existing book before overwrite: " .. tostring(err or target_member)
            end
            backups[#backups + 1] = { target = target_member, backup = backup }
        end
    end

    for index, staged_member in ipairs(staging_members) do
        if path_exists(staged_member) then
            local ok, err = rename_file(staged_member, target_members[index])
            if not ok then
                rollback()
                return nil, "Could not install replacement book: " .. tostring(err or target_members[index])
            end
        end
    end

    for _, item in ipairs(backups) do
        if path_exists(item.backup) then remove_file(item.backup) end
    end
    return target
end

return ExternalAcsm
