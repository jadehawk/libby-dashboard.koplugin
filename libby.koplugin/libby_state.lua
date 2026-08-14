local LibbyState = {}

local SECONDS_PER_DAY = 24 * 60 * 60

function LibbyState.reset_credentials(state)
    if type(state) ~= "table" then
        return false
    end
    local had_identity = state.libby_identity ~= nil
    state.libby_identity = nil
    state.pending_identity = nil
    state.pending_setup_code = nil
    state.pending_blessing = nil
    return had_identity
end

function LibbyState.is_authenticated(state)
    return type(state) == "table"
        and type(state.libby_identity) == "string"
        and state.libby_identity ~= ""
end

function LibbyState.days_remaining(expire_timestamp, now_timestamp)
    if type(expire_timestamp) ~= "number" then
        return nil
    end
    now_timestamp = now_timestamp or os.time()
    if type(now_timestamp) ~= "number" then
        return nil
    end

    local seconds = expire_timestamp - now_timestamp
    if seconds <= 0 then
        return 0
    end
    return math.ceil(seconds / SECONDS_PER_DAY)
end

local function date_ordinal(year, month, day)
    if month <= 2 then
        year = year - 1
        month = month + 12
    end
    return 365 * year
        + math.floor(year / 4)
        - math.floor(year / 100)
        + math.floor(year / 400)
        + math.floor((153 * (month - 3) + 2) / 5)
        + day
end

local function iso_date_days_remaining(value, now_timestamp)
    if type(value) ~= "string" then
        return nil
    end
    local year, month, day = value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
    if not year then
        return nil
    end
    year, month, day = tonumber(year), tonumber(month), tonumber(day)

    local now = os.date("!*t", now_timestamp or os.time())
    local remaining = date_ordinal(year, month, day) - date_ordinal(now.year, now.month, now.day)
    if remaining < 0 then
        return 0
    end
    return remaining
end

function LibbyState.loan_expire_timestamp(loan)
    if type(loan) ~= "table" then return nil end
    local expire = loan.expireTimestamp or loan.expires or loan.expireDate
    if type(expire) == "number" then return expire end
    if type(expire) ~= "string" then return nil end

    local year, month, day, hour, minute, second = expire:match(
        "^(%d%d%d%d)%-(%d%d)%-(%d%d)[T ](%d%d):(%d%d):(%d%d)"
    )
    if not year then
        year, month, day = expire:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
        hour, minute, second = "23", "59", "59"
    end
    if not year then return nil end
    return os.time({
        year = tonumber(year), month = tonumber(month), day = tonumber(day),
        hour = tonumber(hour), min = tonumber(minute), sec = tonumber(second),
        isdst = false,
    })
end

function LibbyState.loan_days_remaining(loan, now_timestamp)
    if type(loan) ~= "table" then
        return nil
    end

    local expire = loan.expireTimestamp or loan.expires or loan.expireDate
    if type(expire) == "number" then
        return LibbyState.days_remaining(expire, now_timestamp)
    end
    return iso_date_days_remaining(expire, now_timestamp)
end

function LibbyState.adobe_formats(loan)
    local formats = {}
    if type(loan) ~= "table" or type(loan.formats) ~= "table" then
        return formats
    end

    for _, format in ipairs(loan.formats) do
        if type(format) == "table" then
            local id = format.id
            if id == "ebook-epub-adobe" or id == "ebook-pdf-adobe" then
                table.insert(formats, id)
            end
        end
    end

    return formats
end

function LibbyState.preferred_adobe_format(loan)
    local formats = LibbyState.adobe_formats(loan)
    for _, id in ipairs(formats) do
        if id == "ebook-epub-adobe" then
            return id
        end
    end
    return formats[1]
end

return LibbyState
