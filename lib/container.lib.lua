os.require_command "docker"
os.require_command "jq"

local store_proto = {}

store_proto.real_name_of = function (origin_name)
	if type(origin_name) ~= "string" then error("Origin container name should be a string") end
	local provider = service:provider "container_name"
	if not provider then return origin_name end
	return provider(origin_name)
end

store_proto.data_path_of = function (origin_name)
	local volumes = stores.volume
	if not volumes then return null end
	return volumes:data_path_of(origin_name)
end

store_proto.network_name_of = function(container)
	local networks = stores.network
	if not networks then return container.name end
	local network = networks:network_of(container)
	if not network then return container.name end
	return network.name
end

function store_proto:container_names()
	local names = array {}
	for key, _ in pairs(self) do names:insert(key) end
	return names
end

function store_proto:container_list()
	local containers = array { }
	for _, value in pairs(self) do containers:insert(value) end
	return containers
end

function store_proto:container_not_null(origin_name)
	local container = self[origin_name] or error("No such container: " + origin_name)
	return container
end

local store_mt = { __index = store_proto }
local store    = setmetatable({}, store_mt)

-- Container methods

local container_proto = {}

function container_proto:state()
	local real_name = self.real_name
	local template = "docker container inspect '%s' 2> /dev/null | jq '.[0].State.Status'"
	local handle = io.popen(template:format(real_name))
	local state_str = handle:read(); handle:close()
	if not state_str then error(string.format("Could not read container state of '%s' from docker!", real_name)) end
	if state_str == "null" then return nil end
	return state_str:gsub('"(%a+)"',"%1")
end

function container_proto:depended_containers()
	local dependencies = self.dependencies
	if dependencies then
		if type(dependencies) == 'string' then return array { store:container_not_null(dependencies) } end

		local list = array {}
		for _, dep in pairs(dependencies) do list:insert(store:container_not_null(dep)) end
		return list
	end
	return array { }
end

function container_proto:information_string()
	local container      = self
	local origin_name    = self.name
	local container_name = self.real_name
	local state          = self:state() or "<unavailable>"

	local template = "Container [ %s ] \n"
	               + "    State        : %s \n"
				   + "    Real Name    : %s \n"
				   + "    Data Path    : %s \n"
				   + "    Dependencies : %s"

	local data_path = store.data_path_of(origin_name) or "<unavailable>"

	local deps = container:depended_containers()
	local dep_str = "<no dependencies>"
	if #deps > 0 then dep_str = deps:join_to_string(", ", function (value) return value.name end) end

	return template:format(origin_name, state, container_name, data_path, dep_str)
end

-- Container DSL

local container_mt = {
	__index = container_proto,
	__call  = function(self, config) self:configure(config) end,
	__metatable = container_proto
}

function container_proto:configure(table)
	for key, value in pairs(table) do
		if (key == "real_name" or key == "name") then goto continue end
		self[key] = value
		::continue::
	end
	return self
end

registry.dsl_context.container = function(name, config)
	local container = setmetatable(config or store[name] or {}, container_mt)
	container.name = name
	container.real_name = store.real_name_of(name)
	store[name] = container
	return container
end

local dependency_resolver = setmetatable({}, {
	__call = function(self, container) return self.create(container) end 
})
local dependency_resolver_mt = { __index = dependency_resolver }
dependency_resolver.create = function(container)
	local root = { container = container, next = nil }
	local state = { priorities = {}, stack = root, root = root, depth = 1 }
	root.next = root
	return setmetatable(state, dependency_resolver_mt)
end
function dependency_resolver:check_cricular(current)
	local root, anchor, pointer = self.root, current, current.next
	while pointer ~= anchor do
		if pointer.container.name == anchor.container.name then error("Cricular dependency: " + self:stack_tostring(anchor)) end
		pointer = pointer.next
	end
end
function dependency_resolver:resolve()
	local current, container = self.stack, self.stack.container
	local name, deps = container.name, container:depended_containers()

	-- update the priority
	local priority = self.priorities[name] or 0
	if self.depth > priority then self.priorities[name] = self.depth end
	
	if #deps <= 0 then return end -- no depdency, exit the iteration

	self:check_cricular(current)

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
function dependency_resolver:stack_tostring(highlight)
	local str, count, pointer = "", 1, self.root
	repeat
		if count > 1 then str = str + " -> " end
		local name = pointer.container.name
		if name == highlight.container.name then 
			str = str + "[" + name + "]"
		else
			str = str + name
		end
		count = count + 1
		pointer = pointer.next
	until pointer == self.root
	return str
end
local __dependency_reverse_sort = function(a, b) return a[1] > b[1] end
local function flatten_dependencies(container)
	local resolver = dependency_resolver(container)
	resolver:resolve()
	return table(resolver.priorities):sort_by_value(__dependency_reverse_sort)
end

local container_create_env_template="CONTAINER_NAME='%s' VOLUME_PATH='%s' NETWORK_NAME='%s' IMAGE_NAME='%s'"
local function create_container_simple(origin_name)
	local container = store:container_not_null(origin_name)
	if container:state() then return end
	local real_name = store.real_name_of(origin_name)
	
	local env = container_create_env_template:format(
		real_name, 
		(store.data_path_of(origin_name) or ("./" + origin_name)),
		(store.network_name_of(container) or ""),
		(container.image or "")
	)

	local create_method = container.create
	local script = ""
	if not create_method then
		script = service.conf_dir + "/" + origin_name + ".create.sh"
		if not fs.is_file_exists(script) then 
			error(string.format("No container create method. Set 'create' command options to container or provide create script '%s'.", script)) 
		end
	else
		script = "docker create " + create_method
	end
	local result, state, exit_code = os.execute(env + " " + script)
	if not result then error(string.format("Create container '%s' failed. Process state: %s, exit code: %d", origin_name, state, exit_code)) end
end

local function create_container(container)
	local state = container:state()
	if state then return end
	local name = container.name
	stdout("Create container '" + name + "'...\n")
	local dependencies = flatten_dependencies(container)
	-- stdout(" !!] %s dependency list: %s \n", name, dependencies:join_to_string(",", function(v,i) return "[ " + i + " : " + v + " ]" end))
	
	-- create containers
	for _, name in ipairs(dependencies) do create_container_simple(name) end
end

local function start_container_simple(container)
	local template = "docker start '%s'"
	local name = container.name
	local real_name = store.real_name_of(name)
	print("Start container: " + name)
	local script = template:format(real_name)
	local result, flag, exit_code = os.execute(template)
	if not result then error(string.format("Could not start container '%s'. Process state: %s, exit code: %d", name, flag, exit_code)) end
end

local function start_container(container)
	local state = container:state()
	if not state then stdout("Container did not created: " + origin_name + "\n"); return end
	if state == "running" then return end
	
	stdout("Start container '" + container.name + "'...\n")
	-- resolve dependencies
	local dependencies = flatten_dependencies(container):filter(function(value) 
		local state = store:container_not_null(value):state()
		if not state then error("Container did not created: " + value) end
		if state == "running" then return false end
		return true
	end)

	-- start all containers
	for _, container in ipair(dependencies) do 
		local name = container.name
		local real_name = store.real_name_of(name)
		print("Start container: " + name)
		local script = template:format(real_name)
	end
end

local function stop_container_simple(container)
	local template = "docker stop '%s'"
	local name = container.name
	local real_name = container.real_name
	print("Stop container: " + name)
	local script = template:format(real_name)
	local result, flag, exit_code = os.execute(script)
	if not result then error(string.format("Container '%s' stop failed. Process state: %s, exit code: %d", name, flag, exit_code)) end
end

local function stop_container(container)
	local state = container:state()
	if state ~= "running" then return end
	print("Stop container '" + container.name + "'...")
	-- resolve dependencies
	local dependencies = flatten_dependencies(container):reverse_in_place():map(function(name)
		return store:container_not_null(name)
	end):filter(function(container) 
		local state = container:state()
		if state ~= "running" then return false end
		return true
	end)
	-- stop all containers
	for _, container in ipairs(dependencies) do stop_container_simple(container) end
end

local function stop_all_containers(containers)
	local dependencies = containers:map(function(container)
		return { container, flatten_dependencies(container):reverse_in_place() }
	end)
	if #dependencies <= 0 then stdout("No container. \n"); return end
	local map = table {}
	for _, entry in ipairs(dependencies) do
		local list = entry[2]
		for index, origin_name in ipairs(list) do
			local weight = map[origin_name] or 0
			weight = weight + index
			map[origin_name] = weight
		end
	end
	local aggregation = map:sort_by_value():map(function(name)
		return store:container_not_null(name)
	end):filter(function(container)
		return "running" == container:state()
	end)
	if #aggregation <= 0 then stdout("All containers are stopped. \n"); return end
	for _, container in ipairs(aggregation) do stop_container_simple(container) end
end

local function remove_container(container)
	stdout("Remove container '" + container.name + "' \n")
	local command = "docker rm '" + container.real_name + "'"
	local result, flag, exit_code = os.execute(command)
	if not result then stdout("Stop container failed. Process state: " + result + ", exit code: " + exit_code + "\n") end
end


-- Handlers

local handlers = {
	--- list all containers
	list = function()
		local containers = store:container_list()
		if #containers <= 0 then stdout("No container defined.\n"); return end
		local str = containers:join_to_string("\n--------------------------------\n", function(container, _, _)
			return container:information_string()
		end)
		stdout(str + "\n")
	end;

	--- show single container
	show = function (origin_name)
		if not origin_name then stdout("Container name required. \n"); return end
		local str = store:container_not_null(origin_name):information_string()
		stdout(str + "\n")
	end;

	--- list container dependencies
	dependencies = function (origin_name)
		if not origin_name then error("Container name required") end
		local container = store:container_not_null(origin_name)
		local dependencies = container:depended_containers()
	
		local str = "Container '" + origin_name + "' has no depdencies"
		if #dependencies <= 0 then print(str); return end
		
		str = "Dependencies of '" + origin_name + "': "
		local deps_str = dependencies:join_to_string(", ", function(value)
			v:information_string()
		end)
		str = str + deps_str
		print(str)
	end;

	--- create container
	create = function (origin_name)
		if not origin_name then
			local containers = store:container_list()
			if #containers <= 0 then stdout("No container defined."); return end
	
			for _,container in ipairs(containers) do create_container(container) end
			stdout("Containes are created. \n")
		else
			create_container(store:container_not_null(origin_name))
			stdout("Container created: " + origin_name + "\n")
		end
	end;

	--- start container
	start = function (origin_name)
		if not origin_name then
			local containers = store:container_list()
			for _, container in ipairs(containers) do start_container(container) end
		else
			start_container(store:container_not_null(origin_name))
		end
	end;

	--- stop container
	stop = function (origin_name)
		if not origin_name then
			stop_all_containers(store:container_list())
		else
			stop_container(store:container_not_null(origin_name))
		end
	end;

	--- remove container
	remove = function(origin_name)
		if not origin_name then
			local list = store:container_list():filter(function(container)
				local state = container:state()
				if not state then return false end
				if state == "running" then
					stdout("Container " + container.name + " is running. Need to stop it first. \n")
					return false
				end
				return true
			end)
			if #list <= 0 then stdout("No container for stop.") end
			for _, container in ipairs(list) do
				remove_container(container)
			end
		else
			remove_container(store:container_not_null(origin_name))
		end
	end
}

-- Entry

local function entry(...)
	local args = table.pack(...)
	local handler_name = args[1] or "list"
	local handler = handlers[handler_name] or error("Unknown command '" + handler_name + "'")
	handler(table.unpack(args, 2))
end

return {
	store = store,
	entry = entry
}
