local library = require "misc.library"
--------------------------------------------------------------------------------------------------------------------------------
if not library "configuration" then -- Configuration helper
--------------------------------------------------------------------------------------------------------------------------------

local conf_proto = {}
local confs_meta = { __index = table.indexer(conf_proto), __metatable = table.protect({ is_instance = true, type = 'configuration' }) }

--- Create new configuration instance
function conf_proto.create(tb)
    assert(tb, "table is required")
    local props = {}
    props.provider = tb.provider or error("provider is required")

end

library.create("configuration", conf_proto, {
    __call = function(self, ...) self.create(...) end
})

end -- END CONFIGURATION
return library "configuration"