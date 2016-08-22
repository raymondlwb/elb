local redis = require 'lib.redtool'
local router = require 'lib.router'
local config = require 'config'
local lock = require 'resty.lock'
local ruleprocess = require 'lib.rule'

local ngx_share = ngx.shared
local dyups = require 'ngx.dyups'


function init_limit_filter()
    -- lock, ensure only one worker does this
    local mutex = lock:new('locks', {timeout = 0})
    local es, err = mutex:lock('init_limit_filter')
    if not es then
        ngx.log(ngx.NOTICE, 'init_limit_filter() called in another worker')
        return
    end

    local rds = redis:new()
    local redis_key = config.NAME .. ':filter'
    local domain_map_key = config.NAME .. ':domainmap'

    -- load limit rule
    local limits, err = rds:hget(redis_key, 'limit')
    if err or not limits then
        ngx.log(ngx.INFO, 'no limit set')
    else
        local limit_rules = cjson.decode(limits)
        for path, rate in pairs(limit_rules) do
            reqlimit:add_or_update_rule(path, rate, rate * 1.2)
        end
        ngx.log(ngx.NOTICE, 'limit rules loaded')
    end

    -- load referrer rule
    local refs, err = rds:hget(redis_key, 'referrer')
    if err or not refs then
        ngx.log(ngx.INFO, 'no referrer set')
    else
        local ref_rules = cjson.decode(refs)
        for uri, regex in pairs(ref_rules) do
            refcheck:add_or_update_rule(uri, regex)
        end
        ngx.log(ngx.NOTICE, 'referrer rules loaded')
    end

    -- load user agent rule
    local uas, err = rds:hget(redis_key, 'ua')
    if err or not uas then
        ngx.log(ngx.INFO, 'no ua set')
    else
        ngx.log(ngx.NOTICE, 'user agent rules loaded')
    end

    -- mutex:unlock()
    ngx.log(ngx.NOTICE, 'all limits loaded')
end


function init_router()
    -- lock, ensure only one worker does this
    local mutex = lock:new('locks', {timeout = 0})
    local es, err = mutex:lock('init_router')
    if not es then
        ngx.log(ngx.NOTICE, 'init_router() called in another worker')
        return
    end

    ruleprocess.load_rules()

    local upstreams = router.get_upstream()
    for backend_key, upstream in pairs(upstreams) do
        dyups.update(backend_key, upstream)
    end

    -- mutex:unlock()
    ngx.log(ngx.NOTICE, 'all routes loaded')
end


-- can only use worker because cosocket is disabled
ngx.timer.at(0, init_limit_filter)
ngx.timer.at(0, init_router)
