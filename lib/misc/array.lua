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

local __default_string_converter = function(v) return tostring(v) end
--- join collection items to string
---@param delimiter? string @delimiter, default is empty string
---@param converter? fun(value : any, key : string|integer, counter : integer):string @optional converter, default is tostring(value)
function array_proto:join_tostring(delimiter, converter)
    local source = self
    local acc, counter = "", 1
    local converter, delimiter = (converter or __default_string_converter), (delimiter or "")
    for k, v in ipairs(source) do
        if counter > 1 then acc = acc .. delimiter end
        local transformed = converter(v, k, counter)
        acc = acc .. transformed
        counter = counter + 1
    end
    return acc
end

--- flatten an array. if value is not a collection type (table or array), add to result directly
---@return array @result array
function array_proto:flatten()
    local source, target = self, array {}
    for _,value in ipairs(source) do
        local value_type = typeof(value)
        if value_type == 'table' or value_type == 'array' then
            for _, item in pairs(value) do
                target:insert(item)
            end
        else target:insert(value)
        end
    end
    return target
end

function array_proto:to_map()
    local source, target = self, table { }
    for index, value in ipairs(source) do
        local k, v = unpack(value)
        if not v then v = k; k = index end
        target[k] = v
    end
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