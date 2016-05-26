local ffi = require "ffi"
local math = require "math"

local ngx_shared = ngx.shared
local setmetatable = setmetatable
local ffi_cast = ffi.cast
local ffi_str = ffi.string
local abs = math.abs
local tonumber = tonumber
local type = type


ffi.cdef[[
    struct limit_req_rec {
        unsigned long rate;  /* integer, 1 corresponds to 1 r/s */
        unsigned long burst; /* integer, 1 corresponds to 1 r/s */
    };
]]
local const_rec_ptr_type = ffi.typeof("const struct limit_req_rec*")
local rec_size = ffi.sizeof("struct limit_req_rec")

local _M = {
    _VERSION = '0.01'
}


local mt = {
    __index = _M
}


function _M.new(indicator_name, storage_name)
    local indicator = ngx_shared[indicator_name]
    local storage = ngx_shared[storage_name]
    if not indicator or not storage then
        return nil, "shared dict not found"
    end

    local self = {
        indicator = indicator,
        storage = storage,
    }

    return setmetatable(self, mt)
end


-- add or update a rule for key
-- key is just host + first uri
-- rate and burst both use r/s as unit
function _M.add_or_update_rule(self, key, rate, burst)
    local dict = self.indicator
    local rec = ffi.new("struct limit_req_rec")
    rec.rate = rate
    rec.burst = burst
    dict:set(key, ffi_str(rec, rec_size))
end


-- delete rule
function _M.delete_rule(self, key)
    local dict = self.indicator
    dict:delete(key)
end


-- show all rules
function _M.all_rules(self)
    local result = {}
    local dict = self.indicator
    local keys = dict:get_keys(0)
    for _, key in ipairs(keys) do
        local v = dict:get(key)
        if type(v) == "string" and #v == rec_size then
            local rec = ffi_cast(const_rec_ptr_type, v)
            result[key] = {rate = tonumber(rec.rate), burst = tonumber(rec.burst)}
        end
    end
    return result
end


-- check incoming request for key
-- key is just host + first uri
-- returns delay and err
-- if delay is nil, err will show error message
-- otherwise delay means to wait delay seconds
function _M.incoming(self, key)
    local storage = self.storage
    local indicator = self.indicator

    -- if no key is specified
    -- test is skipped
    -- just return 0 and 0
    local v = indicator:get(key)
    if not v then
        return 0, ""
    end

    if type(v) ~= "string" or #v ~= rec_size then
        return nil, "shdict abused by other users"
    end

    local rec = ffi_cast(const_rec_ptr_type, v)
    local rate = tonumber(rec.rate)
    local burst = tonumber(rec.burst)

    -- if no storage is found
    -- means test is passed
    local l = storage:get(key)
    if not l then
        storage:set(key, 1, 1)
        return 0, ""
    end

    -- over burst, deny
    if l > burst then
        return nil, "rejected"
    end

    -- < rate, test is passed
    storage:incr(key, 1)
    if l < rate then
        return 0, ""
    end
    -- in (rate, burst), pass and wait
    return (l - rate) / rate, ""
end

return _M
