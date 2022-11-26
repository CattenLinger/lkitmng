local store_proto = {
	volume_dir = (fs.work_dir + "/volumes")
}

local all_volumes = function()
	local containers = stores.container
	if not containers then return array {} end
	return containers:container_list()
end

store_proto.data_path_of = function(self, container_name)
	return (self.volume_dir + "/" + container_name)
end

local store_mt = { __index = store_proto }
local store = setmetatable({}, store_mt)

local function container_date_path_exists(container_name)
	return fs.is_directory_exists(store:data_path_of(container_name))
end

-- Handlers

local handlers = {}
handlers["list"] = function()
	local volumes = all_volumes()
	if #volumes <= 0 then stdout("No Containers.\n"); return end
	local str = volumes:join_to_string("\n--------\n", function(value)
		local str = "Volume of [ " + value.name + " ] \n"
		str = str + "    State     : "
		if container_date_path_exists(value.name) then
			str = str + "Exists"
		else
			str = str + "Missing"
		end
		str = str + "\n"
		str = str + "    Data Path : " + store:data_path_of(value.name)
		return str
	end)
	stdout(str + "\n")
end

-- Entry

local entry = function(...)
	local args = table.pack(...)
	if #args <= 0 then handlers["list"](); return; end
	local sub_command = args[1]
	local handler = handlers[sub_command] or error("Unknown command: " + sub_command)
	handler(table.unpack(args, 2))
end

return {
	entry = entry,
	store = store
}
