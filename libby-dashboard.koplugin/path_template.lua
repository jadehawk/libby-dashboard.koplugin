local PathTemplate = {}

PathTemplate.LEGACY_DEFAULT_TEMPLATE = "{home}/{author:first}/{title}.{ext}"
PathTemplate.DEFAULT_TEMPLATE = "{home}/Libby Books/{author:first}/{series}/{title}.{ext}"

local function trim(value)
    if type(value) ~= "string" then return nil end
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    if value == "" then return nil end
    return value
end

local function creator_name(creator)
    if type(creator) == "string" then return trim(creator) end
    if type(creator) ~= "table" then return nil end
    return trim(creator.name or creator.displayName or creator.fullName)
end

function PathTemplate.first_author(model)
    if type(model) == "table" and type(model.authors) == "table" then
        local name = creator_name(model.authors[1])
        if name then return name end
    end
    return (type(model) == "table" and trim(model.author)) or "Unknown Author"
end

local function split_name(name)
    local parts = {}
    for part in tostring(name or ""):gmatch("%S+") do table.insert(parts, part) end
    if #parts == 0 then return "Unknown", "Author" end
    if #parts == 1 then return parts[1], parts[1] end
    return parts[1], parts[#parts]
end

local function split_sort_name(sort_name)
    if type(sort_name) ~= "string" then return nil, nil end
    local last, first = sort_name:match("^%s*([^,]+),%s*(.-)%s*$")
    if not last or not first or first == "" then return nil, nil end
    return first, last
end

function PathTemplate.author_firstname(model)
    local first = type(model) == "table" and type(model.authors) == "table" and model.authors[1]
    if type(first) == "table" then
        local value = trim(first.firstName or first.firstname or first.givenName)
        if value then return value end
        local sort_first = split_sort_name(first.sortName or first.sort_name)
        if sort_first then return sort_first end
    end
    local value = split_name(PathTemplate.first_author(model))
    return value
end

function PathTemplate.author_lastname(model)
    local first = type(model) == "table" and type(model.authors) == "table" and model.authors[1]
    if type(first) == "table" then
        local value = trim(first.lastName or first.lastname or first.familyName or first.surname)
        if value then return value end
        local _, sort_last = split_sort_name(first.sortName or first.sort_name)
        if sort_last then return sort_last end
    end
    local _, value = split_name(PathTemplate.first_author(model))
    return value
end

function PathTemplate.all_authors(model)
    if type(model) ~= "table" or type(model.authors) ~= "table" then
        return PathTemplate.first_author(model)
    end
    local names = {}
    for _, creator in ipairs(model.authors) do
        local name = creator_name(creator)
        if name then table.insert(names, name) end
    end
    if #names == 0 then return PathTemplate.first_author(model) end
    return table.concat(names, ", ")
end

function PathTemplate.sanitize_component(value, fallback)
    value = tostring(value or "")
    value = value:gsub("[<>:%\"/\\|%?%*]", "_")
    value = value:gsub("[%c]", "_")
    value = value:gsub("%s+", " ")
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    value = value:gsub("[%. ]+$", "")
    if value == "" then return fallback or "Unknown" end
    return value
end

function PathTemplate.resolve(template, model, options)
    options = options or {}
    template = trim(template) or PathTemplate.DEFAULT_TEMPLATE
    local values = {
        home = options.home or ".",
        author = PathTemplate.all_authors(model),
        ["author:first"] = PathTemplate.first_author(model),
        ["author:firstname"] = PathTemplate.author_firstname(model),
        ["author:lastname"] = PathTemplate.author_lastname(model),
        title = type(model) == "table" and model.title or nil,
        series = type(model) == "table" and model.series or nil,
        series_index = type(model) == "table" and model.series_index or nil,
        library = type(model) == "table" and model.library or nil,
        ext = options.ext or (type(model) == "table" and model.ext) or "epub",
    }

    local resolved = template:gsub("{([^{}]+)}", function(token)
        local value = values[token]
        if value == nil or tostring(value) == "" then
            if token == "series" then value = "No Series"
            elseif token == "series_index" then value = "0"
            else value = "Unknown" end
        end
        if token == "home" then
            return tostring(value):gsub("[\\/]+$", "")
        end
        return PathTemplate.sanitize_component(value)
    end)
    resolved = resolved:gsub("\\", "/"):gsub("/+", "/")
    return resolved
end

function PathTemplate.tokens()
    return {
        "{home}", "{author}", "{author:first}",
        "{author:firstname}", "{author:lastname}", "{title}",
        "{series}", "{series_index}", "{library}", "{ext}",
    }
end

function PathTemplate.is_known_token(token)
    local wrapped = "{" .. tostring(token or "") .. "}"
    for _, candidate in ipairs(PathTemplate.tokens()) do
        if candidate == wrapped then return true end
    end
    return false
end

function PathTemplate.validate(template)
    template = trim(template)
    if not template then return nil, "Destination template cannot be empty" end
    for token in template:gmatch("{([^{}]+)}") do
        if not PathTemplate.is_known_token(token) then
            return nil, "Unknown destination token: {" .. token .. "}"
        end
    end
    local stripped = template:gsub("{[^{}]+}", "")
    if stripped:find("{", 1, true) or stripped:find("}", 1, true) then
        return nil, "Destination template contains unmatched braces"
    end
    return true
end

return PathTemplate
