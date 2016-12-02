local redis = require 'lib.redtool'
local router = require 'lib.router'
local config = require 'config'
local lock = require 'resty.lock'
local ruleprocess = require 'lib.rule'

local ngx_share = ngx.shared
local dyups = require 'ngx.dyups'

local monitor = require 'monitor'

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

    mutex:unlock()
    ngx.log(ngx.NOTICE, 'all routes loaded')
end


-- can only use worker because cosocket is disabled
ngx.timer.at(0, init_router)
ngx.timer.at(0, monitor.monitor)
