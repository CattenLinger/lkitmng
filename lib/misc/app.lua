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

function app:msg(...)
    if self.quiet then return end
    stderr(...)
end

function app:info(...)
    if self.quite or not self.verbose then return end
    stderr(...)
end

function app:dbg(...)
    if self.quite or not self.debug then return end
    stderr(...)
end

app = library:create('app', app_proto)
end
return app