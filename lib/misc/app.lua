local fs, library = require "misc.fs", require "misc.library"
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

local function load_feature_file(name, chain)
    local existed = features[name]
    if existed then return existed end

    if chain == nil then chain = {}
    elseif chain[name] then error("Cricular dependency detected: " + array(chain):join_tostring(" -> ", function(value) 
        if value == name
        then return "[" + value + "]"
        else return value
        end
    end))
    end

    chain[name] = true

    local filename = app.path.libraries + "/" + name + ".feature.lua"
    if not fs.is_file_exists(filename) then error("No such feature: " + name) end
    local global, mt = create_feature_load_env({
        feature = function(name) load_feature_file(name, chain) end
    })
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
    local installed_feature_string = array(app:list_feature_files():map(function(value)
        return value:gsub("%.feature%.lua", "")
    end)):join_tostring("\n")

    if(installed_feature_string == "") then installed_feature_string = "<no installed features>" end
    local str = table {
        app:build_help_string();
        "Installed features: (try giving '-h' or '--help' to features for help)\n" + installed_feature_string + "\n\n";
        "-------- Informations --------\n";
        app:build_info_string();
    }:join_tostring("\n")
    
    os.exit(0, str)
end

function app_proto:main()
    app_proto.main = nil
    local subcommand = app.parameters.subcommand
    if #subcommand <= 0 then print_information_and_exit(); return end
    local feature = subcommand[1]
    local feature_args = pack(unpack(subcommand, 2))

end

app = library:create('app', app_proto)
end
return app