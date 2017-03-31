local lock = require 'resty.lock'
local cjson = require 'cjson'
local config = require 'config'
local redis = require 'lib.redtool'
local router = require 'lib.router'
local string = require 'string'
local table = require 'table'
local dyups = require 'ngx.dyups'
local rules = ngx.shared.rules
local utils = require 'utils'

local _M = {}

function update_upstream(data)
    if data['OPER'] == config.UPDATE then
        return router.add_upstream(data['BACKEND'], data['SERVERS'])
    end
    if data['OPER'] == config.DELETE then
        return router.delete_upstream(data['BACKEND'])
    end
end

function update_rule(data)
    if data['OPER'] == config.UPDATE then
        -- router.add_rule 里面加锁了
        return router.add_rule(data['KEY'], data['RULE'])
    end
    if data['OPER'] == config.DELETE then
        return router.delete_rule(data['KEY'])
    end
end

local func_table = {
    UPSTREAM = update_upstream,
    RULE = update_rule
}

function _M.monitor()
    local mutex = lock:new('monitor', {timeout=0, exptime=3})
    local uplock, err = mutex:lock('api')
    if not uplock then
        ngx.log(ngx.NOTICE, 'ELB start monitor in another worker')
        return
    end
    if err then
        ngx.log(ngx.ERR, err)
    end
    local rds = redis:new()
    local update = rds:subscribe(config.CHANNEL_KEY)
    if not update then
        ngx.log(ngx.ERR, 'ELB start monitor failed')
        return
    end
    if err then
        ngx.log(ngx.ERR, err)
        return
    end
    ngx.log(ngx.NOTICE, 'ELB start to monitor')

    while true do
        if ngx.worker.exiting() then
            ngx.log(ngx.NOTICE, 'API monitor exit')
            break
        end
        local res, err = update()
        local sleep_time = config.REDIS_RECONNECT_INTERVAL
        if err and err ~= 'timeout' then
            ngx.log(ngx.ERR, err)
            update = nil
            while not update do
                ngx.log(ngx.ERR, 'Try to reconnect redis')
                ngx.sleep(sleep_time)
                if sleep_time < config.REDIS_RECONNECT_INTERVAL_UPPER then
                    sleep_time = sleep_time * 2
                end
                rds = redis:new()
                update, err = rds:subscribe(config.CHANNEL_KEY)
                if err then
                    ngx.log(ngx.ERR, 'Try to resubscribe: '..err)
                end
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
