package.path = "./libby-dashboard.koplugin/?.lua;" .. package.path

local LibbyClient = require("libby_client")

local calls = {}
local transport = {}
function transport:base64_encode(value)
    assert(value == "Notify Me")
    return "Tm90aWZ5IE1l"
end
function transport:request(request)
    calls[#calls + 1] = request
    if request.base_url == LibbyClient.TAGS_BASE and request.path == "/tags" then
        return {
            status = 200,
            body = {
                tags = {
                    {
                        name = "Notify Me",
                        uuid = "notify-tag",
                        behaviors = { "notify-me", "subscription" },
                        totalTaggings = 2,
                        taggings = {
                            { titleId = "5844282", cardId = "card-1", websiteId = "library-1", titleFormat = "magazine-overdrive" },
                            { titleId = "ebook-1", cardId = "card-1", websiteId = "library-1", titleFormat = "ebook-overdrive" },
                        },
                    },
                },
            },
        }
    end
    if request.base_url == LibbyClient.THUNDER_BASE and request.path == "/media/bulk" then
        assert(request.query["x-client-id"] == "dewey")
        if request.query.titleIds == "5844282" then
            return {
                status = 200,
                body = {
                    {
                        id = "5844282",
                        title = "The New Yorker",
                        recentIssues = { { id = "13572384" }, { id = "13550000" } },
                        type = { id = "magazine" },
                        formats = { { id = "magazine-overdrive" } },
                    },
                },
            }
        end
        assert(request.query.titleIds == "13572384", "latest issue must be resolved from parent recentIssues")
        return {
            status = 200,
            body = {
                {
                    id = "13572384",
                    title = "The New Yorker",
                    parentMagazineTitleId = "5844282",
                    edition = "Sep 14 2026",
                    type = { id = "magazine" },
                    formats = { { id = "magazine-overdrive" } },
                },
            },
        }
    end
    return nil, "unexpected request"
end

local client = LibbyClient.new{
    transport = transport,
    identity = "test-identity",
}
local magazines, err = client:magazine_subscriptions()
assert(magazines, tostring(err))
assert(#magazines == 1)
assert(magazines[1].id == "13572384")
assert(magazines[1].parentMagazineTitleId == "5844282")
assert(magazines[1].cardId == "card-1")
assert(magazines[1].websiteId == "library-1")
assert(magazines[1].magazineSubscription == true)
assert(magazines[1].subscriptionTitleId == "5844282")
assert(calls[1].base_url == LibbyClient.TAGS_BASE)
assert(calls[1].headers.Authorization == "Bearer test-identity")
assert(calls[2].base_url == LibbyClient.THUNDER_BASE)

-- Current Libby accounts may store the current issue id directly in Notify Me.
-- This is the shape observed from the live Magazine Rack API in September 2026.
local direct_issue_transport = {}
function direct_issue_transport:request(request)
    if request.base_url == LibbyClient.TAGS_BASE and request.path == "/tags" then
        return {
            status = 200,
            body = {
                tags = {
                    {
                        name = "Magazine Rack",
                        uuid = "magazine-notify-tag",
                        behaviors = { ["notify-me"] = { type = "subscription" } },
                        totalTaggings = 1,
                        taggings = {
                            { titleId = "13572384", cardId = "card-2", websiteId = "library-2", titleFormat = "magazine" },
                        },
                    },
                },
            },
        }
    end
    if request.base_url == LibbyClient.THUNDER_BASE and request.path == "/media/bulk" then
        assert(request.query.titleIds == "13572384", "current issue tagging must be looked up directly")
        return {
            status = 200,
            body = {
                {
                    id = "13572384",
                    title = "The New Yorker",
                    parentMagazineTitleId = "5844282",
                    edition = "Sep 14 2026",
                    type = { id = "magazine" },
                    formats = { { id = "magazine-overdrive" } },
                },
            },
        }
    end
    return nil, "unexpected direct-issue request"
end

local direct_client = LibbyClient.new{
    transport = direct_issue_transport,
    identity = "test-identity",
}
local direct_magazines, direct_err = direct_client:magazine_subscriptions()
assert(direct_magazines, tostring(direct_err))
assert(#direct_magazines == 1, "current-issue Notify Me tagging must produce one magazine subscription")
assert(direct_magazines[1].id == "13572384")
assert(direct_magazines[1].parentMagazineTitleId == "5844282")
assert(direct_magazines[1].cardId == "card-2")
assert(direct_magazines[1].subscriptionTitleId == "13572384")

local controller_file = assert(io.open("libby-dashboard.koplugin/koreader_controller.lua", "rb"))
local controller_source = controller_file:read("*a")
controller_file:close()
assert(controller_source:find("function KOReaderController:fetch_libby_snapshot()", 1, true),
    "controller must expose one shared full Libby refresh path")
assert(controller_source:find("local subscriptions, subscription_err = self:sync_magazine_subscriptions()", 1, true),
    "full Libby refresh must perform tag-based magazine subscription discovery")
assert(controller_source:find("local snapshot, err = self:fetch_libby_snapshot()", 1, true),
    "saved snapshot refresh must use the shared full refresh path")

local main_file = assert(io.open("libby-dashboard.koplugin/main.lua", "rb"))
local main_source = main_file:read("*a")
main_file:close()
assert(main_source:find("local normalized = self.controller:fetch_libby_snapshot()", 1, true),
    "normal dashboard Refresh must include tag-based magazine subscription discovery")
assert(not main_source:find("local state = self.controller:sync_libby()", 1, true),
    "dashboard Refresh must not bypass magazine subscription discovery with raw sync_libby")
assert(main_source:find('DiagnosticLog.log("[refresh] magazine_subscriptions", "count=" .. tostring(magazine_count))', 1, true),
    "dashboard Refresh should log the discovered magazine subscription count")

print("magazine_subscriptions_test: ok")
