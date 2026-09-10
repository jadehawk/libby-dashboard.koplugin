local MediaRacks = {
    ALL_SCOPE = "__all__",
    AUDIOBOOKS_SCOPE = "__audiobooks__",
    MAGAZINE_SCOPE = "__magazine_rack__",
}

local function copy_item(item)
    local copy = {}
    for key, value in pairs(type(item) == "table" and item or {}) do copy[key] = value end
    return copy
end

local function stable_text(value)
    return tostring(value or ""):lower()
end

local function item_key(item)
    if type(item) ~= "table" then return "" end
    local id = item.id or item.title
    if id == nil then return "" end
    return tostring(id)
end

local function sort_items(items)
    table.sort(items, function(a, b)
        local a_library = stable_text(a.library)
        local b_library = stable_text(b.library)
        if a_library ~= b_library then return a_library < b_library end
        local a_title = stable_text(a.title)
        local b_title = stable_text(b.title)
        if a_title ~= b_title then return a_title < b_title end
        return item_key(a) < item_key(b)
    end)
    return items
end

function MediaRacks.is_synthetic(scope_id)
    return scope_id == MediaRacks.AUDIOBOOKS_SCOPE or scope_id == MediaRacks.MAGAZINE_SCOPE
end

function MediaRacks.group_key(item)
    if type(item) ~= "table" then return "" end
    return tostring(item.rack_group or item.library or "")
end

function MediaRacks.group_counts(items)
    local counts = {}
    for _, item in ipairs(type(items) == "table" and items or {}) do
        local key = MediaRacks.group_key(item)
        counts[key] = (counts[key] or 0) + 1
    end
    return counts
end

function MediaRacks.page_groups(items, first_index, last_index)
    items = type(items) == "table" and items or {}
    local groups = {}
    local counts = MediaRacks.group_counts(items)
    first_index = math.max(1, tonumber(first_index) or 1)
    last_index = math.min(#items, tonumber(last_index) or #items)
    local current
    for index = first_index, last_index do
        local item = items[index]
        local key = MediaRacks.group_key(item)
        if not current or current.key ~= key then
            current = { key = key, count = counts[key] or 0, entries = {} }
            table.insert(groups, current)
        end
        table.insert(current.entries, { item = item, index = index })
    end
    return groups
end

function MediaRacks.grid_positions(items, first_index, last_index, columns)
    columns = math.max(1, tonumber(columns) or 1)
    local positions = {}
    local row = 0
    local groups = MediaRacks.page_groups(items, first_index, last_index)
    for _, group in ipairs(groups) do
        local column = 1
        row = row + 1
        for _, entry in ipairs(group.entries) do
            positions[entry.index] = { row = row, column = column }
            column = column + 1
            if column > columns then
                column = 1
                row = row + 1
            end
        end
        if column == 1 then row = row - 1 end
    end
    return positions, math.max(0, row), groups
end

function MediaRacks.audiobooks(snapshot)
    local items = {}
    for _, loan in ipairs(type(snapshot) == "table" and type(snapshot.loans) == "table" and snapshot.loans or {}) do
        if loan.media_type == "audiobook" and loan.on_hold ~= true then
            local copy = copy_item(loan)
            copy.rack_group = copy.library
            copy.rack_source = "loan"
            table.insert(items, copy)
        end
    end
    return sort_items(items)
end

function MediaRacks.magazines(snapshot)
    snapshot = type(snapshot) == "table" and snapshot or {}
    local items = {}
    local seen = {}
    local subscriptions_by_issue = {}
    local subscriptions_by_parent = {}

    for _, subscription in ipairs(type(snapshot.magazine_subscriptions) == "table" and snapshot.magazine_subscriptions or {}) do
        local issue_key = item_key(subscription)
        local parent_key = tostring(subscription.parent_magazine_title_id or subscription.subscription_title_id or "")
        if issue_key ~= "" then subscriptions_by_issue[issue_key] = subscription end
        if parent_key ~= "" then subscriptions_by_parent[parent_key] = subscription end
    end

    -- If Libby auto-delivers the current subscription issue as a live loan, keep
    -- that loan as the rendered item but merge the subscription state (including
    -- NEW ISSUE) into it. If the live loan is an older issue for the same parent,
    -- skip it and let the subscription's current issue represent the rack title.
    for _, loan in ipairs(type(snapshot.loans) == "table" and snapshot.loans or {}) do
        if loan.media_type == "magazine" and loan.on_hold ~= true then
            local issue_key = item_key(loan)
            local parent_key = tostring(loan.parent_magazine_title_id or "")
            local subscription = subscriptions_by_issue[issue_key]
                or (parent_key ~= "" and subscriptions_by_parent[parent_key] or nil)
            if not subscription or item_key(subscription) == issue_key then
                local copy = copy_item(loan)
                if subscription then
                    copy.magazine_subscription = true
                    copy.magazine_new_issue = subscription.magazine_new_issue == true
                    copy.parent_magazine_title_id = copy.parent_magazine_title_id or subscription.parent_magazine_title_id
                    copy.magazine_frequency = copy.magazine_frequency or subscription.magazine_frequency
                    copy.edition = copy.edition or subscription.edition
                    copy.publish_date = copy.publish_date or subscription.publish_date
                    copy.cover_url = copy.cover_url or subscription.cover_url
                    copy.subscription_title_id = subscription.subscription_title_id
                end
                copy.rack_group = copy.library
                copy.rack_source = "loan"
                local key = item_key(copy)
                if key == "" or not seen[key] then
                    if key ~= "" then seen[key] = true end
                    table.insert(items, copy)
                end
            end
        end
    end

    for _, subscription in ipairs(type(snapshot.magazine_subscriptions) == "table" and snapshot.magazine_subscriptions or {}) do
        local copy = copy_item(subscription)
        copy.media_type = "magazine"
        copy.magazine_subscription = true
        copy.rack_group = copy.library
        copy.rack_source = "subscription"
        local key = item_key(copy)
        if key == "" or not seen[key] then
            if key ~= "" then seen[key] = true end
            table.insert(items, copy)
        end
    end

    return sort_items(items)
end

function MediaRacks.items(snapshot, scope_id)
    if scope_id == MediaRacks.AUDIOBOOKS_SCOPE then return MediaRacks.audiobooks(snapshot) end
    if scope_id == MediaRacks.MAGAZINE_SCOPE then return MediaRacks.magazines(snapshot) end
    return nil
end

function MediaRacks.scope_ids(cards, snapshot)
    local ids = {}
    for _, card in ipairs(type(cards) == "table" and cards or {}) do
        local id = card.id or card.cardId
        if id ~= nil and tostring(id) ~= "" then table.insert(ids, tostring(id)) end
    end
    table.insert(ids, MediaRacks.ALL_SCOPE)
    if #MediaRacks.audiobooks(snapshot) > 0 then table.insert(ids, MediaRacks.AUDIOBOOKS_SCOPE) end
    if #MediaRacks.magazines(snapshot) > 0 then table.insert(ids, MediaRacks.MAGAZINE_SCOPE) end
    return ids
end

return MediaRacks
