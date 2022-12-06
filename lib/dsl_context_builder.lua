local library = require "misc.library"

local dsl_context_template = {
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

local function create_dsl_context(initial)
    local under = setmetatable(initial or {}, { __index = dsl_context_template, __metatable = table.empty })
    return table.overlay(under, {})
end

return library.create("dsl_context", { create = create_dsl_context }, { __call = function(self, ...) return self.create(...) end })