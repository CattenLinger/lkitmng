local array = require "misc.array"
--------------------------------------------------------------------------------------------------------------------------------
if not library "fs" then -- Filesystem lib
--------------------------------------------------------------------------------------------------------------------------------
local fs_proto = fs

local command_list_file = shell:template("ls -1 %q 2> /dev/null")

--- List items under path
---@param path string @target path
---@return array @array of items

function fs_proto:list_files(path)
    local result, error, flag, exit_code = command_list_file(path)
    if not result then return result, error, flag, exit_code end

    local list = array {}
    for item in result:lines() do list:insert(item) end

    return list
end

function fs_proto:init_temp_dir()
	local location = "/tmp/" + os.tempname()
	local success = os.execute(fstring("mkdir -p '%s'", location))
	if not success then error(fstring("Could not create temp directory %q", location)) end
	fs_proto.temp_location = location
	return location
end

function fs_proto:destroy_temp_dir()
	local location = fs_proto.temp_location
	if not location then return false, "Temp directory is not initialized!" end

	local success = os.execute(fstring("rm -rf '%s'", location))
	if not success then error(fstring("Cannot delete temp directory %q", location)) end
end

fs = library:create("fs", fs_proto)
end -- END FS
return fs