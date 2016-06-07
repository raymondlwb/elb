local string = require 'string'
local ngx_shared = ngx.shared
local setmetatable = setmetatable


local _M = {
    _VERSION = '0.01'
}


local mt = {
    __index = _M
}


function _M.new(storage_name)
    local storage = ngx_shared[storage_name]
    if not storage then
        return nil, "shared dict not found"
    end

    local self = {
        storage = storage,
    }

    return setmetatable(self, mt)
end


-- add rule for uri 
-- uri is like hostname + first path
-- referrer must match the regex
function _M.add_or_update_rule(self, uri, regex)
    local dict = self.storage
    dict:set(uri, regex)
end


-- delete rule
function _M.delete_rule(self, uri)
    local dict = self.storage
    dict:delete(uri)
end


-- show all rules
function _M.all_rules(self)
    local result = {}
    local dict = self.storage
    local keys = dict:get_keys(0)
    for _, key in ipairs(keys) do
        result[key] = dict:get(key)
    end
    return result
end


-- check if ref matches uri's corresponding regex
function _M.check(self, uri, ref)
    local storage = self.storage

    -- not found, pass
    local regex = storage:get(uri)
    if not regex then
        return true
    end

    -- found regex and no referrer is set, false
    if ref == nil then
        return false
    end

    -- found and doesn't match, false
    local r = string.match(ref, regex)
    if r == nil then
        return false
    end

    -- found and matches, pass
    return true
end

return _M
