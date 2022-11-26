

local networks_proto = {}

function networks_proto:network_list()
    local list = array { }
    for _, value in pairs(self) do list:insert(value) end
    return list
end

local networks_mt = { __index = networks_proto }
local networks = setmetatable({}, networks_mt)

-- Network

local network_proto = { }

function network_proto:configure(config)
    if not config then return self end
    for key, value in pairs(config) do
        if key == "name" then goto continue end
        self[key] = value
        ::continue::
    end
    return self
end

local network_mt = { __index = network_proto, __call = function(self, config) self:configure(config) end; }

local store_proto = {}

function store_proto:network_of(container)
    local network = container.network
    if not network then
        local default_network = store_proto.default_network
        if not default_network then return nil end
        return networks[default_network]
    end
    local config_type = type(network)

    if config_type == "string" then
        return networks[network]
    elseif config_type == "table" then
        return networks[network.name]
    end
    error("Unknown network configuration type: " + config_type)
end

local store_mt = table.shadow_of(store_proto)
local store = setmetatable({}, store_mt)

registry.dsl_context.network = function(network_name)
    local network = networks[network_name] or setmetatable({}, network_mt)
    network.name = network_name
    networks[network_name] = network
    if not store_proto.default_network then 
        store_proto.default_network = network_name
    end
    return network
end

registry.dsl_context.default_network = function(network)
    local conf_type = type(network)
    if conf_type == "table" then
        store_proto.default_network = network.name
    elseif conf_type == "string" then
        store_proto.default_network = network
    end
end

registry.providers:register("container_name", function(origin_name)
    local default_network = store_proto.default_network
    if not default_network then return origin_name end
    local prefix = default_network
    if type(prefix) == 'table' then prefix = prefix.name end
    return prefix + "." + origin_name
end)

local function __list_networks()
    local network_list = networks:network_list()
    if #network_list <= 0 then stdout("No network configured. \n"); return end
    local str = network_list:join_to_string("\n--------------------------------\n", function(value)
        local str = ""

        return str
    end)
end

local function entry(...)
    __list_networks()
end

return {
    store = store,
    entry = entry,
}