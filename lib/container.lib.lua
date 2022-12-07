os.require_command "docker"
os.require_command "jq"

local fs, dsl_context = require "misc.fs", require "dsl_context_builder"

-- all needed shell commands
local commands = {
	list_config            = shell:template("ls -1 %q 2> /dev/null | grep -E '^.+?\\.container\\.conf$'");
	container_status       = shell:template("docker container inspect '%s' 2> /dev/null | jq '.[0].State.Status'");
	container_start        = shell:template("docker start %q 2> /dev/null");
	container_stop         = shell:template("docker stop  %q 2> /dev/null");
	container_remove       = shell:template("docker rm %q 2> /dev/null");
	container_remove_force = shell:template("docker rm -f %q 2> /dev/null");
}

-- dsl method registry
local dsl_methods = table { }

-- config data store
local store = {
	containers = table { };
}

function store:container_not_null(name)
	local container = self.containers[name]
	if not container then error(fstring("Container %q undefined.", name)) end
	return container
end

-- config manager
local configs = {
	path = app.path.home + "/conf.d";
}
configs.dir_exists = fs.is_directory_exists(configs.path)

--- list all configuration files. if no file or faailed to load, returns an empty array.
---@return array @array of files
function configs:files()
	local collection, path = array {}, self.path
	if not is_config_dir_exists then goto return_collection end

	local result, success, flag, exit_code = commands.list_config(path)
	if not success then
		app:dbg("Failed to list configuration files from %q. Process state %s, exit code %d.", path, flag, exit_code)
		goto return_collection
	end

	for file in result:lines() do collection:insert(file) end

	::return_collection::
	return collection
end

--- reload all config files
---@return table @dsl context
function configs:reload()
	local path, dir_exists = self.path, self.dir_exists
	if not dir_exists then
		app:msg("Configuration directory %q does not exists, try to create one.", path)
		if not fs:mkdir(config_path) then error(fstring("Could not create configuration directory %q !", path)) end
	end

	local context, files = dsl_context(dsl_context:dump()), self:files()
	if files:count() <= 0 then goto return_context end

	-- reset store
	store = table {}
	for _, file in files:pairs() do
		local chunk, err = loadfile(config_path + file, "t", context)
		if not chunk then error(fstring("Could not load configuration file %q. Error: %s", file, err)) end

		local success, result, err = pcall(chunk)
		if not success then error(fstring("Could not load configuration file %q. Error: %s", file, err)) end
	end

	::return_context::
	return context
end

-- Container methods

local container_proto = {}

--- Read container status from docker
--- json path: `.[0].State.Status`
---@return string|nil @string state of container, if docker returns `null` then it will returns `nil`
function container_proto:state()
	local real_name = self.real_name
	local result, success, flag, exit_code = commands.container_status(real_name)
	result = result or error(fstring("Could not read container state of %q. Process status: %s, exit code %d", real_name, flag, exit_code))

	local state_str = result:trim()
	if state_str == "null" then return nil end
	return state_str:gsub('"(%a+)"',"%1")
end

--- get depended containers
---@return array @list of containers
function container_proto:depended_containers()
	local dependencies = self.dependencies
	if not dependencies then return array {} end
	if type(dependencies) == 'string' then return array { store:container_not_null(dependencies) } end
	return table.map(dep, function(value) store:container_not_null(value) end)
end

--- build string information for a container
---@return string @string information
function container_proto:info_tostring()
	return table {
		fstring("Container [ %s ] \n"     , self.name);
		fstring("    State        : %s \n", self:state() or "<unavailable>");
		fstring("    Real Name    : %s \n", self.real_name);
		fstring("    Data Path    : %s \n", self:data_path());
		fstring("    Dependencies : %s \n", (function()
			local deps = self:depended_containers()
			if deps:count() > 0 then return deps:join_tostring(", ", function (value) return value.name end) end
			return "<no dependencies>"
		end)());
	}:join_tostring()
end

-- Container

local container_mt = {
	__index = container_proto,
	__call  = function(self, config) self:configure(config) end,
	__metatable = table.protected({
		__index     = container_proto;
		is_instance = true;
		type        = "container";
	})
}

function container_proto:configure(table)
	for key, value in pairs(table) do
		if (key == "real_name" or key == "name") then goto continue end
		self[key] = value
		::continue::
	end
	return self
end

-- DSL

function dsl_methods:container(name, config)
	assert(name and (typeof(name) == "string"), "#name(string) is required")

	local container = setmetatable(config or store[name] or {}, container_mt)
	container.name = name
	container.real_name = container_proto.real_name_of(name)
	local container_store = store.containers or {}
	container_store[name] = container
	store.containers = container_store
	return container
end

local dependency_resolver = require "dependency_resolver"

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
