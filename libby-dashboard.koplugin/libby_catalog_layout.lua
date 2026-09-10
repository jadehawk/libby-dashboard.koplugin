local Layout = {}

Layout.TALL_PORTRAIT_ASPECT = 1.75

local function positive(value, fallback)
    value = tonumber(value)
    if value and value > 0 then return value end
    return fallback or 1
end

function Layout.isTallPortrait(width, height)
    width = positive(width)
    height = positive(height)
    return height > width and (height / width) >= Layout.TALL_PORTRAIT_ASPECT
end

function Layout.browserModalGeometry(screen_width, screen_height, scale)
    screen_width = positive(screen_width)
    screen_height = positive(screen_height)
    scale = scale or function(value) return value end

    local margin = scale(16)
    local tall = Layout.isTallPortrait(screen_width, screen_height)
    local modal_width_ratio = tall and 0.92 or 0.88
    local modal_width = math.max(scale(360), math.floor(screen_width * modal_width_ratio))
    modal_width = math.min(math.max(1, screen_width - margin), modal_width)

    local modal_height
    if tall then
        -- Tall phones have abundant vertical space, but tying the card height to the
        -- screen height makes the cover dominate the card. Size it primarily from
        -- the available width and use the extra height for metadata + actions.
        modal_height = math.max(
            scale(300),
            math.floor(math.min(screen_height * 0.46, modal_width * 0.78))
        )
    else
        -- Match the catalog browser's proven ~30% vertical budget on ordinary
        -- e-reader/tablet aspect ratios.
        modal_height = math.max(scale(230), math.floor(screen_height * 0.30))
    end
    modal_height = math.min(math.max(1, screen_height - margin), modal_height)

    return {
        tall = tall,
        width = modal_width,
        height = modal_height,
    }
end

function Layout.detailGeometry(width, height, pad, action_height, gap, button_count, scale, tall)
    width = positive(width)
    height = positive(height)
    pad = math.max(0, tonumber(pad) or 0)
    action_height = positive(action_height)
    gap = math.max(0, tonumber(gap) or 0)
    button_count = math.max(1, math.floor(tonumber(button_count) or 1))
    scale = scale or function(value) return value end
    tall = tall == true

    -- The action row spans the full card width below the cover + metadata, so
    -- the number of bottom buttons must not squeeze the cover column.
    local minimum_info_width = scale(260)

    if tall then
        local action_width = math.max(1, width - 2 * pad)
        local button_width = math.max(1, math.floor((action_width - (button_count - 1) * gap) / button_count))
        local top_height = math.max(1, height - action_height - 3 * pad)
        local max_cover_height = math.max(1, top_height - 2 * pad)
        local max_cover_width = math.max(1, math.floor(width * 0.38))
        local cover_width = math.max(1, math.min(math.floor(max_cover_height * 0.66), max_cover_width))
        local cover_height = math.max(1, math.min(max_cover_height, math.floor(cover_width / 0.66)))
        local info_width = math.max(1, width - cover_width - 4 * pad)

        return {
            tall = true,
            cover_width = cover_width,
            cover_height = cover_height,
            info_width = info_width,
            top_height = top_height,
            action_width = action_width,
            button_width = button_width,
        }
    end

    local action_width = math.max(1, width - 2 * pad)
    local button_width = math.max(1, math.floor((action_width - (button_count - 1) * gap) / button_count))
    local top_height = math.max(1, height - action_height - 3 * pad)
    local max_cover_height = math.max(1, top_height - 2 * pad)
    local desired_cover_width = math.max(1, math.floor(max_cover_height * 0.66))
    local max_cover_width = math.max(1, width - minimum_info_width - 4 * pad)
    local cover_width = math.max(1, math.min(desired_cover_width, max_cover_width))
    local cover_height = math.max(1, math.min(max_cover_height, math.floor(cover_width / 0.66)))
    local info_width = math.max(1, width - cover_width - 4 * pad)

    return {
        tall = false,
        cover_width = cover_width,
        cover_height = cover_height,
        info_width = info_width,
        top_height = top_height,
        action_width = action_width,
        button_width = button_width,
    }
end

return Layout
