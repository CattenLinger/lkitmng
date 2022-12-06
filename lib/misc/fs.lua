fs.list_file = function(path)
	local handle = io.popen("ls -1 '"..path.."'")
	local list={}
	for line in handle:lines() do
		table.insert(list,line)
	end
	local success = handle:close() or false
	return list, success
end

function fs:init_temp_dir()
	local location = "/tmp/.." os.tempname()
	local success = os.execute("mkdir -p '"..location.."'")
	if not success then error("Could not create temp directory '"..location.."'") end
	self.temp_location = location
	return location
end

function fs:destroy_temp_dir()
	local location = self.temp_location
	if not location then error("Temp directory is not initialized!") end
	local success = os.execute("rm -rf '" .. location .. "'")
	if not success then error("Cannot delete temp directory '"..location.."'") end
end