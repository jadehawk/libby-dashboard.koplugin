local Version = {}

function Version.parse(value)
    if type(value) ~= "string" then return nil end
    local normalized = value:gsub("^v", "")
    local major, minor, patch, revision = normalized:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if major then
        return {
            tonumber(major),
            tonumber(minor),
            tonumber(patch),
            tonumber(revision),
        }
    end

    major, minor, patch = normalized:match("^(%d+)%.(%d+)%.(%d+)$")
    if not major then return nil end
    return {
        tonumber(major),
        tonumber(minor),
        tonumber(patch),
        0,
    }
end

function Version.is_newer(candidate, current)
    local candidate_parts = Version.parse(candidate)
    local current_parts = Version.parse(current)
    if not candidate_parts or not current_parts then return false end

    for index = 1, 4 do
        if candidate_parts[index] ~= current_parts[index] then
            return candidate_parts[index] > current_parts[index]
        end
    end
    return false
end

return Version
