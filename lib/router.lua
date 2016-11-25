local cjson = require 'cjson'
local redis = require 'lib.redtool'
local config = require 'config'
local _M = {}
local domain_key = config.DOMAIN_KEY
local upstream_key = config.UPSTREAM_KEY
local rule_index_key = config.NAME .. ':rules'
local channel_key = config.CHANNEL_KEY

local rules = ngx.shared.rules

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
    local _, err  =rds:hset(upstream_key, backend, servers)
    if err then return err end
    local msg = {
        TYPE = 'UPSTREAM',
        OPER = config.UPDATE,
        BACKEND = backend,
        SERVERS = servers
    }
    local _, err = rds:publish(channel_key, cjson.encode(msg))
    if err then return err end
end

function _M.delete_upstream(backend)
    local rds = redis:new()
    local _, err = rds:hdel(upstream_key, backend)
    if err then return err end
    local msg = {
        TYPE = 'UPSTREAM',
        OPER = config.DELETE,
        BACKEND = backend
    }
    rds:publish(channel_key, cjson.encode(msg))
    if err then return err end
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

function _M.add_rule(domain, rule)
    local key = config.NAME .. ':' .. domain
    local rds = redis:new()

    rds:init_pipeline()
    rds:hset(rule_index_key, key, domain)
    rds:set(key, rule)
    local msg = {
        TYPE = 'RULE',
        OPER = config.UPDATE,
        KEY  = key,
        RULE = rule
    }
    rds:publish(channel_key, cjson.encode(msg))
    rds:commit_pipeline()
end

function _M.delete_rule(domains)
    local rds = redis:new()
    rds:init_pipeline()
    for _, domain in ipairs(domains) do
        local key = config.NAME .. ':' .. domain
        rds:hdel(index_key, key)
        rds:del(key)
        local msg = {
            TYPE = 'RULE',
            OPER = config.DELETE,
            KEY = key
        }
        rds:publish(channel_key, cjson.encode(msg))
    end
    rds:commit_pipeline()
end

function _M.get_rule()
    local res = {}
    local rule_records = rules:get_keys(0)
    for _, key in ipairs(rule_records) do
        local tmp = rules:get(key)
        if tmp then
            res[key] = cjson.decode(tmp)
        end
    end
    return res
end

return _M
