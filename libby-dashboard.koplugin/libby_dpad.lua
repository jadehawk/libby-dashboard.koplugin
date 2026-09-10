local Dpad = {}

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

local function append_group(bindings, group)
    if group then table.insert(bindings, { group }) end
end

function Dpad.is_touch_device(device)
    if not device then return false end
    if type(device.isTouchDevice) == "function" then
        local ok, value = pcall(device.isTouchDevice, device)
        if ok then return value == true end
    end
    if type(device.isTouch) == "function" then
        local ok, value = pcall(device.isTouch, device)
        if ok then return value == true end
    end
    return false
end

-- Keep the hardware aliases aligned with libbee. Older Kindles may report the
-- center button as Select/Return and their page keys as LPg*/RPg* instead of
-- the generic KOReader input groups.
function Dpad.catalog_key_events(device)
    local events = {
        DpadBack = { { "Back" }, { "Escape" }, { "Esc" } },
        DpadPrevPage = { { "PgUp" }, { "PgBack" }, { "Prev" }, { "LPgBack" }, { "RPgBack" } },
        DpadNextPage = { { "PgDn" }, { "PgFwd" }, { "Next" }, { "LPgFwd" }, { "RPgFwd" } },
        DpadUp = { { "Up" } },
        DpadDown = { { "Down" } },
        DpadLeft = { { "Left" } },
        DpadRight = { { "Right" } },
        DpadPress = { { "Press" }, { "Enter" }, { "Return" }, { "Select" } },
        DpadMenu = { { "Menu" }, { "F10" } },
    }

    local groups = device and device.input and device.input.group or nil
    if groups then
        append_group(events.DpadBack, groups.Back)
        append_group(events.DpadPrevPage, groups.PgBack)
        append_group(events.DpadNextPage, groups.PgFwd)
        append_group(events.DpadUp, groups.Up)
        append_group(events.DpadDown, groups.Down)
        append_group(events.DpadLeft, groups.Left)
        append_group(events.DpadRight, groups.Right)
        append_group(events.DpadPress, groups.Press)
        append_group(events.DpadPress, groups.Enter)
        append_group(events.DpadMenu, groups.Menu)
    end
    return events
end

function Dpad.dialog_key_events(device)
    local events = {
        DpadBack = { { "Back" }, { "Escape" }, { "Esc" } },
        DpadUp = { { "Up" } },
        DpadDown = { { "Down" } },
        DpadLeft = { { "Left" } },
        DpadRight = { { "Right" } },
        DpadPress = { { "Press" }, { "Enter" }, { "Return" }, { "Select" } },
    }
    local groups = device and device.input and device.input.group or nil
    if groups then
        append_group(events.DpadBack, groups.Back)
        append_group(events.DpadUp, groups.Up)
        append_group(events.DpadDown, groups.Down)
        append_group(events.DpadLeft, groups.Left)
        append_group(events.DpadRight, groups.Right)
        append_group(events.DpadPress, groups.Press)
        append_group(events.DpadPress, groups.Enter)
    end
    return events
end

function Dpad.active_action_index(actions, preferred)
    local count = type(actions) == "table" and #actions or 0
    if count == 0 then return nil end
    preferred = clamp(tonumber(preferred) or 1, 1, count)
    for offset = 0, count - 1 do
        local index = ((preferred - 1 + offset) % count) + 1
        if type(actions[index]) == "function" then return index end
    end
    return nil
end

function Dpad.next_action_index(actions, current, delta)
    local count = type(actions) == "table" and #actions or 0
    if count == 0 then return nil end
    local index = clamp(tonumber(current) or 1, 1, count)
    local step = tonumber(delta) and tonumber(delta) < 0 and -1 or 1
    for _ = 1, count do
        index = ((index - 1 + step) % count) + 1
        if type(actions[index]) == "function" then return index end
    end
    return Dpad.active_action_index(actions, current)
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

function Dpad.page_for(index, per_page)
    per_page = math.max(1, tonumber(per_page) or 1)
    index = math.max(1, tonumber(index) or 1)
    return math.floor((index - 1) / per_page) + 1
end

function Dpad.page_bounds(page, per_page, count)
    count = math.max(0, tonumber(count) or 0)
    per_page = math.max(1, tonumber(per_page) or 1)
    local pages = math.max(1, math.ceil(count / per_page))
    page = clamp(tonumber(page) or 1, 1, pages)
    local first = (page - 1) * per_page + 1
    local last = math.min(count, first + per_page - 1)
    if count == 0 then first, last = 1, 0 end
    return first, last, pages
end

function Dpad.first_index_for_page(page, per_page, count)
    local first, last = Dpad.page_bounds(page, per_page, count)
    if last < first then return nil end
    return first
end

function Dpad.index_on_page(index, page, per_page, count)
    local first, last = Dpad.page_bounds(page, per_page, count)
    if last < first then return nil end
    return clamp(tonumber(index) or first, first, last) - first + 1
end

-- Page-local grid movement. Horizontal movement can request a page turn at the
-- first/last visible item; vertical movement never silently changes pages.
function Dpad.move_page_local(index, direction, columns, page, per_page, count)
    count = math.max(0, tonumber(count) or 0)
    if count == 0 then return nil, 0 end
    columns = math.max(1, tonumber(columns) or 1)
    local first, last, pages = Dpad.page_bounds(page, per_page, count)
    index = clamp(tonumber(index) or first, first, last)
    local local_index = index - first + 1
    local page_count = last - first + 1

    if direction == "left" then
        if local_index > 1 then return index - 1, 0 end
        if page > 1 then return Dpad.first_index_for_page(page - 1, per_page, count), -1 end
    elseif direction == "right" then
        if local_index < page_count then return index + 1, 0 end
        if page < pages then return Dpad.first_index_for_page(page + 1, per_page, count), 1 end
    elseif direction == "up" then
        if local_index > columns then return index - columns, 0 end
    elseif direction == "down" then
        local wanted = local_index + columns
        if wanted <= page_count then return first + wanted - 1, 0 end
        local row_start = math.floor((local_index - 1) / columns) * columns + 1
        if row_start + columns <= page_count then return last, 0 end
    end
    return index, 0
end

function Dpad.move_visual_grid(positions, index, direction)
    local current = type(positions) == "table" and positions[index] or nil
    if not current then return index end
    local target_row = current.row
    if direction == "up" then target_row = current.row - 1
    elseif direction == "down" then target_row = current.row + 1
    elseif direction == "left" then
        for candidate_index, position in pairs(positions) do
            if position.row == current.row and position.column == current.column - 1 then return candidate_index end
        end
        return index
    elseif direction == "right" then
        for candidate_index, position in pairs(positions) do
            if position.row == current.row and position.column == current.column + 1 then return candidate_index end
        end
        return index
    else
        return index
    end

    if target_row < 1 then return index end
    local best_index, best_distance
    for candidate_index, position in pairs(positions) do
        if position.row == target_row then
            local distance = math.abs(position.column - current.column)
            if best_distance == nil or distance < best_distance
                or (distance == best_distance and position.column < positions[best_index].column) then
                best_index = candidate_index
                best_distance = distance
            end
        end
    end
    return best_index or index
end

-- Retained for callers/tests that only need clamped global movement.
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

return Dpad
