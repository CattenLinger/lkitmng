local table = require "misc.table"
--------------------------------------------------------------------------------------------------------------------------------
if not library then -- Library
--------------------------------------------------------------------------------------------------------------------------------
local library_proto = {}

local registry = table {}
library_proto.registry = table.protect({}, { __index = registry:indexer() })

function library_proto:create(name, proto, mt)
	if registry[name] then error(fstring("Library %q already exists", name)) end
	local lib_mt = { __index = table.indexer(proto), __metatable = table.protect({ __lib_name = name }) }
	if mt then table.dump(mt, lib_mt) end
	local lib = table.protect({}, lib_mt)
	registry[name] = lib
	return lib
end

library = table.protect({}, {
	__index = table.indexer(library_proto),
	__call = function(self, name) return registry[name] end
})
end -- END
return library