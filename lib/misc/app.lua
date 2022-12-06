local fs, library = require "misc.fs", require "misc.library"
--------------------------------------------------------------------------------------------------------------------------------
if not library "app" then -- App Lib
--------------------------------------------------------------------------------------------------------------------------------
local app_proto = app
--- show message via stderr to user, controlled by `app.quite`
---@vararg string @string with optional formatting
function app_proto:msg(...) if self.quiet then return end; stderr(...) end

--- show verbose info via stderr to user, controlled by `app.verbose`
---@vararg string @string with optional formatting
function app_proto:info(...) if self.quite or not self.verbose then return end; stderr(...) end

--- show debug message via stderr to user, controlled by `app.debug`
---@vararg string @string with optional formatting
function app_proto:dbg(...) if self.quite or not self.debug then return end; stderr(...) end


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

local features_proto = {}

function features_proto:has_entry()   return (not (not self.entry))   end
function features_proto:has_service() return (not (not self.service)) end

--- get all services, or get feature's services
---@param feature_name? string @optional feature name, if not present then get all available services
---@return table|nil @containing all available service name as key, available as value. if no such feature then returns nil.
function app_proto:services(feature_name)
    local service_features = features:filter(function(value) return value:has_service() end)
    local collection = table {}

    -- if feature_name presented
    if feature_name then
        local feature = service_features[feature_name]
        if not feature then return nil end

        for key, value in pairs(feature) do
            collection[key] = true
        end

        return collection
    end

    -- else get all service name
    for key, value in service_features:pairs() do
        for name in pairs(value) do
            if not collection[name] then collection[name] = true end
        end
    end
    return collection
end

--- get a service function by path name
--- path name should be 'service_name.feature_name', feature_name is optional,
--- if feature name not presented, will use first matched service.
function app_proto:service(path)
    local elements = array{}
    for name in path:gmatch("([^.]+)") do elements:insert(name) end
    local name, feature_name = unpack(elements)
    if feature_name then
        local services = (features[feature_name] or {}).service
        if not services then return nil end
        return services[name]
    end

    local all_features = features:filter(function(value) return value:has_service() end)
    for _, value in all_features:pairs() do
        for key, func in pairs(value) do
            if key == name then return func end
        end
    end
    return nil
end

local function create_feature(name, proto)
    if features[name] then error(fstring("Feature %q already exists", name)) end
    local feature = table.protect({}, {
        __index = table.indexer(proto, features_proto),
        __call = function(self, ...) self:entry(...) end,
        __metatable = table.protect({ lib_name = name, is_instance = true, type = 'feature' })
    })
    features[name] = feature
    return feature
end

local function create_feature_load_env(initial) return table.overlay(_G, initial) end

local function load_feature(name, chain)
    local existed = features[name]
    if existed then return existed end

    if chain == nil then chain = {} elseif chain[name] then error("Cricular dependency detected: " + array(chain):join_tostring(
        " -> ", 
        function(value) 
            if value == name then return "[" + value + "]" else return value end
        end) + " -> " + "[" + name + "]")
    end

    chain[name] = true

    local filename = app.path.libraries + "/" + name + ".feature.lua"
    if not fs.is_file_exists(filename) then error("No such feature: " + name) end
    local global, mt = create_feature_load_env({
        features = function(name) 
            local feature = load_feature(name, chain)
            if not feature.service then return table.empty end
            return table.protected({}, { __index = feature.service })
        end;
        feature = create_feature;
    })
    local block, err = loadfile(filename, "bt", global)
    if not block then return nil, fstring("Could not load feature %q, error: %s", name, err) end
    
    local _, feature, err = pcall(block)
    if not feature then return nil, fstring("Cloud not evaluate feature %q, error: %s", name, err) end

    if (not typeof(feature) == 'feature') or (not feature:has_entry()) then 
        error(fstring("Invalid definition of feature %q. Created by 'create_feature' and entry function are required.", name)) 
    end
    features[name] = feature
    return feature
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

function app_proto:feature(name)
    return self.features[name]
end

function app_proto:main()
    app_proto.main = nil
    local subcommand = app.parameters.subcommand
    if #subcommand <= 0 then print_information_and_exit(); return end

    local feature_name = subcommand[1]
    local feature, err = load_feature(feature_name)
    if not feature then os.exit(1, fstring("Could not load feature %q, error: %s", feature_name, err)) end
    feature:entry(unpack(subcommand, 2))
end

app = library:create('app', app_proto)
end
return app