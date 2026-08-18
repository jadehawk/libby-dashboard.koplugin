package.path = "./libby-dashboard.koplugin/?.lua;" .. package.path

local files = {}
local function exists(path)
    return files[path] ~= nil
end

package.loaded["util"] = {
    pathExists = exists,
}
package.loaded["external_acsm"] = nil
local ExternalAcsm = require("external_acsm")

local target = "/books/Author/Title.epub"
assert(not ExternalAcsm.pathOccupied(target, exists))
files[target .. ".lic"] = "rights"
assert(ExternalAcsm.pathOccupied(target, exists), "license sidecar must count as an occupied destination")
files[target .. ".lic"] = nil
files[target] = "old-book"
assert(ExternalAcsm.pathOccupied(target, exists), "existing book must count as an occupied destination")

local staging = assert(ExternalAcsm.stagingPath(target, exists))
assert(staging == "/books/Author/Title.libby-dashboard-replacement-1.epub")
files[staging] = "reserved"
local staging2 = assert(ExternalAcsm.stagingPath(target, exists))
assert(staging2 == "/books/Author/Title.libby-dashboard-replacement-2.epub")
files[staging] = nil

local function rename_file(from, to)
    if not files[from] then return nil, "missing source" end
    files[to] = files[from]
    files[from] = nil
    return true
end

local function remove_file(path)
    files[path] = nil
    return true
end

files[target] = "old-book"
files[target .. ".lic"] = "old-license"
files[staging] = "new-book"
files[staging .. ".lic"] = "new-license"
local installed = assert(ExternalAcsm.replace(staging, target, exists, rename_file, remove_file))
assert(installed == target)
assert(files[target] == "new-book", "overwrite must install the replacement book at the original target")
assert(files[target .. ".lic"] == "new-license", "overwrite must replace the license sidecar")
assert(not files[staging] and not files[staging .. ".lic"], "staging files must be moved away")
assert(not files[target .. ".libby-dashboard-overwrite-backup"], "successful overwrite must clean book backup")
assert(not files[target .. ".lic.libby-dashboard-overwrite-backup"], "successful overwrite must clean license backup")

files[target] = "old-book-rollback"
files[target .. ".lic"] = "old-license-rollback"
files[staging] = "new-book-rollback"
files[staging .. ".lic"] = "new-license-rollback"
local function failing_rename(from, to)
    if from == staging .. ".lic" then return nil, "simulated failure" end
    return rename_file(from, to)
end
local replaced, replace_err = ExternalAcsm.replace(staging, target, exists, failing_rename, remove_file)
assert(not replaced and replace_err:match("Could not install replacement book"))
assert(files[target] == "old-book-rollback", "failed overwrite must restore the existing book")
assert(files[target .. ".lic"] == "old-license-rollback", "failed overwrite must restore the existing license")

files[staging] = "temporary-book"
files[staging .. ".lic"] = "temporary-license"
files[staging .. ".rights"] = "temporary-rights"
ExternalAcsm.cleanup(staging, exists, remove_file)
assert(not files[staging] and not files[staging .. ".lic"] and not files[staging .. ".rights"])

print("external_acsm_overwrite_test: ok")
