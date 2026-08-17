local dom = require("adobe.util.dom")
local koutil = require("util")

local EpubMetadata = {}

local function trim(value)
    if type(value) ~= "string" then return nil end
    value = value:match("^%s*(.-)%s*$")
    return value ~= "" and value or nil
end

local function localName(node)
    if type(node) ~= "table" or type(node._name) ~= "string" then return nil end
    return node._name:match("([^:]+)$")
end

local function collectElements(node, name, out)
    out = out or {}
    if type(node) ~= "table" then return out end
    if node._type == "ELEMENT" and localName(node) == name then
        out[#out + 1] = node
    end
    for _, child in ipairs(node._children or {}) do
        if child._type == "ELEMENT" then
            collectElements(child, name, out)
        end
    end
    return out
end

local function nodeText(node)
    return trim(dom.textOf(node))
end

local function metadataFromRoot(root)
    if type(root) ~= "table" then return {} end

    local result = {}
    local titles = collectElements(root, "title")
    result.title = titles[1] and nodeText(titles[1]) or nil

    local creators = collectElements(root, "creator")
    if #creators > 0 then
        result.authors = {}
        for _, creator in ipairs(creators) do
            local name = nodeText(creator)
            if name then result.authors[#result.authors + 1] = { name = name } end
        end
        if #result.authors > 0 then result.author = result.authors[1].name end
    end

    local metas = collectElements(root, "meta")
    local calibreSeries
    local calibreIndex
    local collections = {}
    local collectionOrder = {}

    for _, meta in ipairs(metas) do
        local attrs = meta._attr or {}
        local name = attrs.name
        local property = attrs.property
        local content = trim(attrs.content)
        local text = nodeText(meta)

        if name == "calibre:series" then
            calibreSeries = content or text
        elseif name == "calibre:series_index" then
            calibreIndex = content or text
        elseif property == "belongs-to-collection" then
            local id = trim(attrs.id) or ("collection-" .. tostring(#collectionOrder + 1))
            collections[id] = collections[id] or {}
            collections[id].name = text or content
            collectionOrder[#collectionOrder + 1] = id
        elseif property == "collection-type" then
            local ref = trim(attrs.refines)
            if ref then
                ref = ref:gsub("^#", "")
                collections[ref] = collections[ref] or {}
                collections[ref].type = text or content
            end
        elseif property == "group-position" then
            local ref = trim(attrs.refines)
            if ref then
                ref = ref:gsub("^#", "")
                collections[ref] = collections[ref] or {}
                collections[ref].index = text or content
            end
        end
    end

    if calibreSeries then
        result.series = calibreSeries
        result.series_index = calibreIndex
    else
        local selected
        for _, id in ipairs(collectionOrder) do
            local collection = collections[id]
            if collection and collection.name and collection.type == "series" then
                selected = collection
                break
            end
        end
        if not selected then
            for _, id in ipairs(collectionOrder) do
                local collection = collections[id]
                if collection and collection.name then
                    selected = collection
                    break
                end
            end
        end
        if selected then
            result.series = selected.name
            result.series_index = selected.index
        end
    end

    return result
end

local function parseXmlMetadata(xml)
    if type(xml) ~= "string" or xml == "" then return nil, "Missing XML metadata" end
    local ok, root = pcall(dom.parse, xml)
    if not ok or type(root) ~= "table" then
        return nil, "Could not parse XML metadata"
    end
    return metadataFromRoot(root)
end

function EpubMetadata.fromAcsm(path)
    local xml = koutil.readFromFile(path, "rb")
    if not xml then return nil, "Could not read ACSM metadata" end
    return parseXmlMetadata(xml)
end

function EpubMetadata.fromEpub(path)
    local ok, Archiver = pcall(require, "ffi/archiver")
    if not ok or not Archiver or not Archiver.Reader then
        return nil, "EPUB metadata reader is unavailable"
    end
    local reader = Archiver.Reader:new()
    if not reader:open(path) then
        return nil, reader.err or "Could not open EPUB"
    end

    local containerXml = reader:extractToMemory("META-INF/container.xml")
    if not containerXml then
        local err = reader.err or "EPUB is missing META-INF/container.xml"
        reader:close()
        return nil, err
    end

    local opfPath = containerXml:match("full%-path%s*=%s*\"([^\"]+)\"")
        or containerXml:match("full%-path%s*=%s*'([^']+)'")
    if not opfPath then
        reader:close()
        return nil, "EPUB container does not identify an OPF package"
    end

    local opf = reader:extractToMemory(opfPath)
    if not opf then
        local err = reader.err or ("Could not read EPUB package: " .. opfPath)
        reader:close()
        return nil, err
    end
    reader:close()

    return parseXmlMetadata(opf)
end

function EpubMetadata.merge(primary, fallback)
    primary = type(primary) == "table" and primary or {}
    fallback = type(fallback) == "table" and fallback or {}
    local result = {}
    for key, value in pairs(fallback) do result[key] = value end
    for key, value in pairs(primary) do
        local meaningful = value ~= nil and value ~= ""
        if type(value) == "table" and next(value) == nil then meaningful = false end
        if meaningful then result[key] = value end
    end
    return result
end

EpubMetadata._parseXmlMetadata = parseXmlMetadata

return EpubMetadata
