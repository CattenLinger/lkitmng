local library = require "misc.library"

local proto = {}
local instance_mt = table.protect({ __index = table.indexer(proto), is_instance = true, type = "dependency_resolver" })

--- create a dependency resolve state
---@generic T : any
---@param obj T @obj that has dependencies
---@param id_provider fun(obj : T):string @provider that provides object identity
---@param deps_provider fun(obj:T):array  @provider that provides depended object
---@return table @resolve state
function proto.create(obj, id_provider, deps_provider)
    local root = { ref = obj, next = nil }
    local state = { stack = root, root = root, depth = 1 }
    root.next = root
    return setmetatable(state, {
        __index = table.indexer({ id_provider = id_provider, deps_provider = deps_provider , priorities = {} }, proto);
        __metatable = instance_mt;
    })
end

local function check_cricular(self, current)
	local root, anchor, pointer, id_provider = self.root, current, current.next, self.id_provider
	while pointer ~= anchor do
		if id_provider(pointer.ref) == id_provider(anchor.ref) then error("Cricular dependency: " + self:stack_tostring(anchor)) end
		pointer = pointer.next
	end
end

function proto:resolve()
	local current, ref, id_provider, deps_provider = self.stack, self.stack.ref, self.id_provider, self.deps_provider
	local name, deps = id_provider(ref), deps_provider(ref)

	-- update the priority
	local priority = self.priorities[name] or 0
	if self.depth > priority then self.priorities[name] = self.depth end
	
	if #deps <= 0 then return end -- no depdency, exit the iteration

	check_cricular(self, current)

	for _, dep in ipairs(deps) do
		-- insert current to the cycled linkedlist
		local next = { container = dep, next = current.next }
		current.next = next
		self.stack = next
		self.depth = self.depth + 1
		-- resolve deps recursively
		self:resolve()
		-- remove current from the cycled linkedlist
		current.next = next.next
		next.next = nil
		self.depth = self.depth - 1
	end
end

function proto:stack_tostring(highlight)
	local str, count, pointer, id_provider = "", 1, self.root, self.id_provider
	repeat
		if count > 1 then str = str + " -> " end
		local name = id_provider(pointer.ref)
		if name == id_provider(highlight.ref) then 
			str = str + "[" + name + "]"
		else
			str = str + name
		end
		count = count + 1
		pointer = pointer.next
	until pointer == self.root
	return str
end

local __reverse_sort = function(a, b) return a[1] > b[1] end

return function(obj, id_provider, deps_provider)
    local resolver = proto.create(obj, id_provider, deps_provider)
    resolver:resolve()
    local items = table(resolver.priorities):map(function(key, value) return { key, value } end)
    items:sort(__reverse_sort)
    return items:map(function(value) return value end)
end