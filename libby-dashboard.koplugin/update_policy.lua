local UpdatePolicy = {}

function UpdatePolicy.should_prompt(candidate_version, current_version, skipped_version, is_newer)
    if type(candidate_version) ~= "string" or candidate_version == "" then return false end
    if type(current_version) ~= "string" or current_version == "" then return false end
    if type(is_newer) ~= "function" or not is_newer(candidate_version, current_version) then return false end
    return candidate_version ~= skipped_version
end

return UpdatePolicy
