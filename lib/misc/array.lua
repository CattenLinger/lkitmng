--------------------------------------------------------------------------------------------------------------------------------
if not array then
--------------------------------------------------------------------------------------------------------------------------------
local array_proto = {}

--- Reverse this array in place, return the origin table reference
---@param arr table
---@return table
array.reverse_in_place = function(arr)
	local n = #arr
	local m = n / 2
	for i = 1, m do arr[i], arr[n - i + 1] = arr[n - i + 1], arr[i] end
	return arr
end

array.reversed = function(arr)
	local result = array { }
	for i=#arr, 1, -1 do result[#result + 1] = arr[i] end
	return result
end

--- Wrap a table as operatable array
---@param arr table
---@return table
array.wrap = function(arr)
	return setmetatable(arr, { __index = array })
end

end -- END
return array