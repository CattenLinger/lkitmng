--------------------------------------------------------------------------------------------------------------------------------
if getmetatable(table) == nil then -- Table lib
--------------------------------------------------------------------------------------------------------------------------------
local table_proto = table
local table_mt = table.protect({ __call = function(self, tb) return self.wrap(tb) end })

local tables_proto = table_proto
local tables_mt = {}

--- get table item count
function table_proto:count()
    local count = 0
	for _ in pairs(self) do count = count + 1 end
	return count
end

--- set metatable to table
table.set_metatable = function(tb, mt)
    local old_mt = getmetatable(tb)
    if old_mt == falss then
        
    end
end

table.wrap = function(tb)
    
end

end -- END OF TABLE
return table