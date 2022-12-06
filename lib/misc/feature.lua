--
-- Setting up
--

--- service storage
local service_private  = { lib_dir  = fs.work_dir + "/lib", conf_dir = fs.work_dir + "/conf.d" }

service_private.provider = function(self, name)
	local provider = registry.providers[name]
	if not provider then return nil end
	if type(provider) ~= 'function' then error("'" + name + "' is not a provider!") end
	return provider
end

local service_shadow = table.shadow_of(service_private)
service = setmetatable({}, service_shadow)

--- feature function storage
local features_private = {}
local features_shadow  = table.shadow_of(features_private)
features = setmetatable({}, features_shadow)

--- feature data storage
local stores_private = {}
local stores_shadow  = table.shadow_of(stores_private)
stores = setmetatable({}, stores_shadow)

--- public registry
local registry_private = {
	dsl_context = {
		ipairs = iparis,
		next = next,
		pairs = pairs,
		rawequals = rawequals,
		rawget = rawget,
		rawset = rawset,
		select = select,
		tonumber = tonumber,
		type = type,
		unpack = table.unpack,
		pack = table.pack,
		string = string,
		table = table,
		math = math,
		os = {
			date = os.date,
			difftime = os.difftime,
			time = os.time,
		},
		print = print,
		array = array
	}
}
local dsl_context_shadow = { __index = registry_private.dsl_context, __metatable = registry_private.dsl_context }
registry_private.dsl_result = setmetatable({}, dsl_context_shadow)

local providers_private = {}
providers_private.register = function(_, name, func)
	if type(func) ~= 'function' then error("Registry provider should be a function, not '" + type(func) + "'") end
	providers_private[name] = func
	return func
end
local providers_shadow = table.shadow_of(providers_private)
registry_private.providers = setmetatable({}, providers_shadow)

local registry_shadow = table.shadow_of(registry_private)
registry = setmetatable({}, registry_shadow)

service_private.reload_configuration_file = function(self)
	local conf_dir = self.conf_dir
	if not fs.is_directory_exists(conf_dir) then
		stderr("Configuration directory '" + confDir + "' does not exists.")
		stderr("Please create one and write some configuration in it.")
		return
	end

	local handle = io.popen("ls -1 '" + conf_dir + "' | grep -E '^.+?\\.lua$'")
	local conf_file_list = {}
	for line in handle:lines() do table.insert(conf_file_list, line) end

	if #conf_file_list <= 0 then
		stderr("No configuration present.")
		stderr("Write some configuration in " + conf_dir + " with suffix '.lua'")
		return
	end

	for _, filename in ipairs(conf_file_list) do
		local file = io.open(conf_dir + "/" + filename)
		local content = file:read("*a")
						file:close()

		local dsl_context = setmetatable({}, dsl_context_shadow)
		local block, err = load(content, filename + " <config>", 't', dsl_context)
		if not block then error("Failed to load configuration. Reason: " + tostring(err)) end
		local success, error = pcall(block)
		if not success then 
			stderr("Failed to evaluate configuration '%s'\nReason: %s\n", filename, tostring(error)); 
			os.exit(1)
		end
		registry_private.dsl_result = dsl_context
	end
end

-- Load lib dir 
if fs.is_directory_exists(service_private.lib_dir) then package.path = package.path + service_private.lib_dir end

local function use_feature(name)
	-- did loaded, no action
	if features[name] or stores[name] then return end
	local lib_dir = service.lib_dir;

	if not fs.is_directory_exists(lib_dir) then error("Library path '" + lib_dir + "' does not exists!") end
	local path = lib_dir + "/" + name + ".lib.lua"
	if not fs.is_file_exists(path) then error("Unknown feature '" + name + "'"); end

	local file = io.open(path)
	local block, err = load(file:read("*a"), name + " <feature>", 't', _ENV)
	                   file:close()

	if not block then error(tostring(err)) end
	local result = block()

	-- load feature entry if present
	local entry = result.entry
	if entry then
		if type(entry) ~= 'function' then error("Feature of '" + name + "' did not return function type!") end
		features_private[name] = entry
	end

	-- load feature store if present
	local store = result.store
	if store then
		if type(store) ~= 'table' then error("Store of '" + name + "' did not return table type!") end
		stores_private[name] = store
	end
end

local function all_features()
	local list={}
	local handle = io.popen("ls -1 '" + service_private.lib_dir + "' 2>/dev/null | grep -E '^.+?\\.lib\\.lua$' | sed -E 's/(.+?)\\.lib\\.lua$/\\1/'")
	for line in handle:lines() do 
		if line ~= "" then table.insert(list, line) end 
	end
	handle:close()
	return list
end

local function print_help()
	print "Service Entry"
	print "Usage: service [feature name] <args...> "
	stdout("Available features:")
	local featureList = all_features()
	if #featureList <= 0 then
		print " (No available commands)"
	else
		for _,command in ipairs(featureList) do stdout(" " + command) end
		print ""
	end
	print ""
	print_information()
end

local function print_information()
	print "-- Information --------"
	print("     Entry : " + os.basename())
	print("Executable : " + os.executable())
	print("   Lib Dir : " + service.lib_dir)
	print("Config Dir : " + service.conf_dir)
end

local function main(args)
	if #args <= 0 then print_help(); os.exit(0); end
	local feature = args[1]
	for _, argv in ipairs(args) do 
		if (argv == '-v' or argv == '--verbose') then __verbose__ = true end 
	end
	if feature == "--help" or feature == "-h" then printHelp(); os.exit(1) end
	if feature == "--info" or feature == "-i" then printInformation(); os.exit(1) end

	for _, name in ipairs(all_features()) do use_feature(name) end
	local entry = features[feature]
	if entry then 
		service:reload_configuration_file()
		entry(table.unpack(args, 2)) 
	else
		stdout("[i] This feature has no command \n")
	end
end

local _, error = pcall(main, arg)
if fs.temp_location then fs:destroy_temp_dir() end
if error then stderr("Error: " + error + "\n"); os.exit(1); end
