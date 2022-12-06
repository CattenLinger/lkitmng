local table = require "misc.table"
--------------------------------------------------------------------------------------------------------------------------------
if not array then -- Array lib
--------------------------------------------------------------------------------------------------------------------------------
local array_proto = setmetatable({}, { __index = table })
---@class array : table

--- Reverse this array in place, return the origin table reference
---@param arr table
---@return table
function array_proto:reverse_in_place()
    local arr = self
    local n = #arr
	local m = n / 2
	for i = 1, m do arr[i], arr[n - i + 1] = arr[n - i + 1], arr[i] end
	return arr
end

--- Reverse an array
---@return array @reversed new array
function array_proto:reversed()
    local source, target = self, array { }
	for i=#arr, 1, -1 do target[#result + 1] = source[i] end
	return target
end

local arraies_mt = { __index = table.indexer(array_proto), is_instance = true, type = 'array' }
--- Wrap a table as operatable array
---@param arr table
---@return table
array_proto.wrap = function(arr) return table.set_metatable(arr, arraies_mt) end

local array_mt = table.protect({
    __index = table.indexer(array_proto),
    __call = function(self, ...) return array.wrap(...) end
})

array = table.protect({}, array_mt)

end -- END
return array