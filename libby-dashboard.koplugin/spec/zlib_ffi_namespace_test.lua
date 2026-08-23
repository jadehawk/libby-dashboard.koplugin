package.path = "./libby-dashboard.koplugin/?.lua;" .. package.path

package.loaded["adobe.util.zlib"] = nil
package.loaded["ffi"] = nil

local saw_private_stream = false

-- Simulate KOReader (or another plugin) having already declared zlib's normal
-- z_stream_s type in LuaJIT's process-wide FFI namespace before we load.
package.preload["ffi"] = function()
    return {
        cdef = function(declarations)
            if declarations:find("struct%s+z_stream_s") then
                error("attempt to redefine pre-existing z_stream_s")
            end
            if declarations:find("struct%s+libby_z_stream_s") then
                saw_private_stream = true
            end
        end,
        load = function()
            return {}
        end,
    }
end

local ok, zlib_or_err = pcall(require, "adobe.util.zlib")
assert(ok, tostring(zlib_or_err))
assert(type(zlib_or_err) == "table")
assert(saw_private_stream, "Libby zlib wrapper must use a plugin-private stream type")

package.preload["ffi"] = nil
package.loaded["ffi"] = nil
package.loaded["adobe.util.zlib"] = nil

print("zlib ffi namespace test passed")
