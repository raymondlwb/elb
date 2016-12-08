local _M = {}
local cjson = require 'cjson'
local lock = require 'resty.lock'
local dyups = require 'ngx.dyups'
local upstream = require 'ngx.upstream'
local config = require 'config'
local redis = require 'lib.redtool'
local rules = ngx.shared.rules
local upstream_key = config.UPSTREAM_KEY
local rule_index_key = config.NAME .. ':rules'
local channel_key = config.CHANNEL_KEY

function _M.add_upstream(backend, servers)
    local status, err = dyups.update(backend, servers)
    if status ~= ngx.HTTP_OK then
        return err
    end
end

function _M.delete_upstream(backend)
    local status, err = dyups.delete(backend)
    if status ~= ngx.HTTP_OK then
        return err
    end
end

function _M.get_upstreams()
    local result = {}
    local us = upstream.get_upstreams()
    for _, u in ipairs(us) do
        local srvs, err = upstream.get_servers(u)
        if not srvs then return nil, err end
        result[u] = srvs
    end
    return result, nil
end

 -- 这个函数是用来初始化的时候载入 upstream 数据的！
function _M.load_upstream()
    local rds = redis:new()
    local rs, err = rds:hgetall(upstream_key)
    if err or not rs then
        rs = {}
    end

    local r = {}
    for i = 1, #rs, 2 do
        local status, err = dyups.update(rs[i], rs[i+1])
        if status ~= ngx.HTTP_OK then
            ngx.log(ngx.ERR, err)
        end
    end
end

function _M.add_rule(key, rule)
    local mutex = lock:new('rules', {timeout=0, exptime=3})
    local rlock, err = mutex:lock('add'..key)
    if not rlock then
        return key..': updated in another worker '
    end
    if err then return err end

    local succ, err, _ = rules:set(key, rule)
    mutex:unlock()
    if not succ then return err end
end

function _M.delete_rule(key)
    local mutex = lock:new('rules', {timeout=0, exptime=3})
    local rlock, err = mutex:lock('delete'..key)
    if not rlock then
        return key .. ': deleted in another worker '
    end
    if err then return err end

    local succ, err, _ = rules:delete(key)
    mutex:unlock()
    if not succ then return err end
end

function _M.get_rule()
    local res = {}
    local rule_records = rules:get_keys(0)
    for _, key in ipairs(rule_records) do
        ngx.log(ngx.NOTICE, key)
        local tmp = rules:get(key)
        if tmp then
            --res[key] = cjson.decode(tmp)
            res[key] = tmp
        end
    end
    return res
end

-- 启动 ELB 时从 redis 中载入数据
function _M.load_rules()
    local index_name = config.NAME .. ':rules'
    local rds = redis:new()
    local rs, err = rds:hgetall(index_name)
    if err then
        ngx.log(ngx.ERR, err)
        return
    end
    if not rs then
        return
    end
    for i = 1, #rs, 2 do
        key = rs[i]
        rule = rds:get(rs[i])
        if rule then
            local succ, err, _ = rules:set(key, rule)
            if not succ and err ~= 'exists' then ngx.log(ngx.ERR, err) end
        end
    end
end

return _M
