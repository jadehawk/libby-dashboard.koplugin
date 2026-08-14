local PathTemplate = require("path_template")

local KOReaderStorage = {}

local function nonempty(value)
    return type(value) == "string" and value ~= "" and value or nil
end

function KOReaderStorage.home_dir(reader_settings, device, cwd)
    if type(reader_settings) == "table" and type(reader_settings.readSetting) == "function" then
        local ok, value = pcall(reader_settings.readSetting, reader_settings, "home_dir")
        if ok and nonempty(value) then
            return value
        end
    end

    if type(device) == "table" and nonempty(device.home_dir) then
        return device.home_dir
    end

    return nonempty(cwd) or "."
end

function KOReaderStorage.destination(template, model, options)
    options = options or {}
    local home = KOReaderStorage.home_dir(options.reader_settings, options.device, options.cwd)
    return PathTemplate.resolve(template, model, {
        home = home,
        ext = options.ext,
    })
end

return KOReaderStorage
