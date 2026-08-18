local LibbyState = require("libby_state")

local LoanModel = {}

local function first_nonempty(...)
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        if type(value) == "string" and value ~= "" then
            return value
        end
    end
end

function LoanModel.card_name(card)
    if type(card) ~= "table" then
        return "Unknown library"
    end
    local library = type(card.library) == "table" and card.library or nil
    return first_nonempty(
        library and library.name,
        card.libraryName,
        card.name,
        library and library.websiteId,
        card.advantageKey
    ) or "Library card"
end

function LoanModel.title(loan)
    if type(loan) ~= "table" then
        return "Untitled"
    end
    return first_nonempty(loan.title, loan.parentTitle, loan.sortTitle) or "Untitled"
end

function LoanModel.authors(loan)
    if type(loan) ~= "table" then
        return {}
    end
    if type(loan.creators) == "table" and #loan.creators > 0 then
        return loan.creators
    end
    if type(loan.creator) == "table" then
        return { loan.creator }
    end
    local fallback = first_nonempty(loan.firstCreatorName, loan.author)
    if fallback then
        return { { name = fallback, sortName = loan.firstCreatorSortName } }
    end
    return {}
end

function LoanModel.author(loan)
    local authors = LoanModel.authors(loan)
    if type(authors[1]) == "table" then
        return first_nonempty(authors[1].name, authors[1].displayName, authors[1].fullName)
    end
    return authors[1]
end

function LoanModel.library_name(loan, cards)
    if type(loan) ~= "table" or type(cards) ~= "table" then
        return nil
    end
    local card_id = loan.cardId
    if card_id == nil then
        return nil
    end
    local wanted = tostring(card_id)
    for _, card in ipairs(cards) do
        if type(card) == "table" then
            local candidate = card.id or card.cardId
            if candidate ~= nil and tostring(candidate) == wanted then
                return LoanModel.card_name(card)
            end
        end
    end
    return nil
end

local function href(value)
    if type(value) == "string" and value ~= "" then
        return value
    end
    if type(value) == "table" then
        return first_nonempty(value.href, value.url)
    end
end

function LoanModel.cover_url(loan)
    if type(loan) ~= "table" then
        return nil
    end
    local covers = type(loan.covers) == "table" and loan.covers or nil
    if covers then
        for _, key in ipairs({ "cover510Wide", "cover300Wide", "cover150Wide", "large", "medium", "small" }) do
            local value = href(covers[key])
            if value then
                return value
            end
        end
    end
    return href(loan.cover) or href(loan.coverUrl) or href(loan.coverURL)
end

function LoanModel.series(loan)
    if type(loan) ~= "table" then return nil, nil end
    local detailed = type(loan.detailedSeries) == "table" and loan.detailedSeries or nil
    local name = detailed and first_nonempty(detailed.seriesName) or first_nonempty(loan.series)
    local index = detailed and (detailed.readingOrder or detailed.rank) or nil
    return name, index
end

function LoanModel.media_type(loan)
    if type(loan) ~= "table" then return "ebook" end

    for _, format in ipairs(type(loan.formats) == "table" and loan.formats or {}) do
        if type(format) == "table" then
            local format_id = tostring(format.id or ""):lower()
            local format_name = tostring(format.name or ""):lower()
            local fulfillment_type = tostring(format.fulfillmentType or ""):lower()
            local format_text = format_id .. " " .. format_name .. " " .. fulfillment_type
            if format_text:find("audio", 1, true) then return "audiobook" end
            if format_text:find("magazine", 1, true) or format_text:find("periodical", 1, true) then return "magazine" end
            if format_id == "ebook-media-do" or fulfillment_type == "media-do" then return "comic" end
        end
    end

    local type_info = type(loan.type) == "table" and loan.type or nil
    local value = first_nonempty(
        type_info and type_info.id,
        type_info and type_info.name,
        loan.typeId,
        loan.mediaType,
        loan.type
    )
    value = tostring(value or ""):lower()
    if value:find("audio", 1, true) then return "audiobook" end
    if value:find("magazine", 1, true) or value:find("periodical", 1, true) then return "magazine" end
    return "ebook"
end

function LoanModel.non_adobe_format_label(loan)
    if type(loan) ~= "table" or type(loan.formats) ~= "table" then return nil end
    local labels, seen = {}, {}
    local function add(label)
        if not seen[label] then
            seen[label] = true
            table.insert(labels, label)
        end
    end
    for _, format in ipairs(loan.formats) do
        if type(format) == "table" then
            local format_id = tostring(format.id or ""):lower()
            if format_id == "ebook-kindle" then add("Kindle")
            elseif format_id == "ebook-overdrive" then add("Libby App") end
        end
    end
    if #labels == 0 then return nil end
    return table.concat(labels, " / ")
end

function LoanModel.from_loan(loan, cards)
    local series, series_index = LoanModel.series(loan)
    return {
        id = type(loan) == "table" and loan.id or nil,
        card_id = type(loan) == "table" and loan.cardId or nil,
        title = LoanModel.title(loan),
        author = LoanModel.author(loan),
        authors = LoanModel.authors(loan),
        series = series,
        series_index = series_index,
        library = LoanModel.library_name(loan, cards),
        days_remaining = LibbyState.loan_days_remaining(loan),
        expires_at = LibbyState.loan_expire_timestamp(loan),
        adobe_format = LibbyState.preferred_adobe_format(loan),
        media_type = LoanModel.media_type(loan),
        non_adobe_format_label = LoanModel.non_adobe_format_label(loan),
        cover_url = LoanModel.cover_url(loan),
        raw = loan,
    }
end

function LoanModel.list(loans, cards)
    local result = {}
    for _, loan in ipairs(loans or {}) do
        table.insert(result, LoanModel.from_loan(loan, cards))
    end
    return result
end

return LoanModel
