local lock = require 'resty.lock'
local cjson = require 'cjson'
local config = require 'config'
local redis = require 'lib.redtool'
local string = require 'string'
local table = require 'table'
local dyups = require 'ngx.dyups'
local rules = ngx.shared.rules
local utils = require 'utils'

local _M = {}

function upstream_refresh(data)
    if data['OPER'] == config.UPDATE then
        local ok, err = dyups.update(data['BACKEND'], data['SERVERS'])
        if ok ~= ngx.HTTP_OK then
            return err
        end
    end
    if data['OPER'] == config.DELETE then
        local ok, err = dyups.delete(data['BACKEND'])
        if ok ~= ngx.HTTP_OK then
            return err
        end
    end
end

function rule_refresh(data)
    local mutex = lock:new('rules', {timeout=0, exptime=3})
    local rlock, err = mutex:lock('rule')
    if not rlock then
        ngx.log(ngx.ERR, ' rule updated in another worker ')
    end
    if err then
        return err
    end

    if data['OPER'] == config.UPDATE then
        local succ, err, _ = rules:set(data['KEY'], data['RULE'])
        if not succ then
            return err
        end
    end
    if data['OPER'] == config.DELETE then
        local succ, err, _ = rules:delete(data['KEY'])
        if not succ then
            return err
        end
    end

    mutex:unlock()
end

local func_table = {
    UPSTREAM = upstream_refresh,
    RULE = rule_refresh
}

function _M.monitor()
    local mutex = lock:new('monitor', {timeout=0, exptime=3})
    local uplock, err = mutex:lock('api')
    if not uplock then
        ngx.log(ngx.NOTICE, ' ELB start monitor in another worker ')
        return
    end
    if err then
        ngx.log(ngx.ERR, err)
    end
    local rds = redis:new()
    local update = rds:subscribe(config.CHANNEL_KEY)
    if not update then
        ngx.log(ngx.ERR, ' ELB start monitor failed ')
        return
    end
    if err then
        ngx.log(ngx.ERR, err)
        return
    end
    ngx.log(ngx.NOTICE, ' ELB start to monitor ')

    while true do
        if ngx.worker.exiting() then
            ngx.log(ngx.NOTICE, ' api monitor exit ')
            break
        end
        local res, err = update()
        if err and err ~= 'timeout' then
            ngx.log(ngx.ERR, err)
            update = nil
            while not update do
                update = rds:subscribe(channel)
            end
        end

        if res then
            local data = cjson.decode(res[3])
            local err = func_table[data['TYPE']](data)
            if err then ngx.log(ngx.ERR, err) end
        end
    end
end

return _M
