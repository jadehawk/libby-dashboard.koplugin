local Dpad = {}

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

function Dpad.find_index(loans, selected_key, key_fn)
    if type(loans) ~= "table" or #loans == 0 then return nil end
    if selected_key ~= nil and type(key_fn) == "function" then
        local wanted = tostring(selected_key)
        for index, loan in ipairs(loans) do
            if tostring(key_fn(loan)) == wanted then return index end
        end
    end
    return 1
end

function Dpad.move_grid(index, direction, columns, count)
    count = math.max(0, tonumber(count) or 0)
    if count == 0 then return nil end
    columns = math.max(1, tonumber(columns) or 1)
    index = clamp(tonumber(index) or 1, 1, count)

    if direction == "left" then
        return math.max(1, index - 1)
    elseif direction == "right" then
        return math.min(count, index + 1)
    elseif direction == "up" then
        return math.max(1, index - columns)
    elseif direction == "down" then
        return math.min(count, index + columns)
    end
    return index
end

function Dpad.page_for(index, per_page)
    index = math.max(1, tonumber(index) or 1)
    per_page = math.max(1, tonumber(per_page) or 1)
    return math.floor((index - 1) / per_page) + 1
end

function Dpad.first_index_for_page(page, per_page, count)
    count = math.max(0, tonumber(count) or 0)
    if count == 0 then return nil end
    page = math.max(1, tonumber(page) or 1)
    per_page = math.max(1, tonumber(per_page) or 1)
    return math.min(count, (page - 1) * per_page + 1)
end

return Dpad
