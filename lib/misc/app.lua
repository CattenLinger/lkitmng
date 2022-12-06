local fs, feature = require "misc.fs", require "misc.feature"
--------------------------------------------------------------------------------------------------------------------------------
if not library "app" then -- App Lib
--------------------------------------------------------------------------------------------------------------------------------
local app_proto = app

local features = table {}
app_proto.features = table.protect({}, { __index = features:indexer() })

local command_list_feature = shell:template("ls -1 %q | grep -E '^.+?\\.feature\\.lua$'")
--- List all installed feature files
function app_proto:list_feature_files()
    local target, path = array {}, app.path.libraries
    local result, _, flag, exit_code = command_list_feature(path)
    if not result then error(fstring("Could not list %q. Process state: %s, exit code %s", path, flag, exit_code)) end
    for line in result:lines() do target:insert(line) end
    return target
end

local function create_feature_load_env(initial)
    return table.overlay(_G, initial)
end

local function load_feature_file(name)
    local filename = app.path.libraries + "/" + name + ".feature.lua"
    if not fs.is_file_exists(filename) then error("No such feature: " + name) end
    local global, mt = create_feature_load_env({})
    local package, err = loadfile(filename, "bt", global)
    if err then return nil, fstring("Could not load feature %q, error: %s", name, err) end
    if not typeof(package) == 'feature' then error(fstring("Invalid definition of feature %q", name)) end
    features[name] = package
    return package
end

function app_proto:msg(...)
    if self.quiet then return end
    stderr(...)
end

function app_proto:info(...)
    if self.quite or not self.verbose then return end
    stderr(...)
end

function app_proto:dbg(...)
    if self.quite or not self.debug then return end
    stderr(...)
end

local function print_information_and_exit()
    local str = table {
        app:build_help_string();
        "Installed features: " + app:list_feature_files():map(function(value) return value:gsub("%.feature%.lua", ""):join_to_string(", ") end);
        app:build_info_string();
    }:join_tostring("\n")
    
    os.exit(0, str)
end

function app_proto:main()
    app_proto.main = nil
    if #app.parameters.subcommand <= 0 then print_information_and_exit(); return end

end

app = library:create('app', app_proto)
end
return app