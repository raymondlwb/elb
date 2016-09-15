local redis = require 'lib.redtool'
local config = require 'config'
local name = config.NAME

local _M = {}
local domain_key = name .. ':domainmap'
local upstream_key = name .. ':upstream'

function _M.add_domain(domain, key)
    local rds = redis:new()
    rds:hset(domain_key, domain, key)
end

function _M.delete_domain(domain)
    local rds = redis:new()
    rds:hdel(domain_key, domain)
end

function _M.get_domain()
    local rds = redis:new()
    local rs, err = rds:hgetall(domain_key)
    if err or not rs then
        rs = {}
    end

    local r = {}
    for i = 1, #rs, 2 do
        r[rs[i]] = rs[i + 1]
    end
    return r
end

function _M.add_upstream(backend, servers)
    local rds = redis:new()
    rds:hset(upstream_key, key, upstream)
end

function _M.delete_upstream(backend)
    local rds = redis:new()
    rds:hdel(upstream_key, backend)
end

function _M.get_upstream()
    local rds = redis:new()
    local rs, err = rds:hgetall(upstream_key)
    if err or not rs then
        rs = {}
    end

    local r = {}
    for i = 1, #rs, 2 do
        r[rs[i]] = rs[i + 1]
    end
    return r
end


return _M
