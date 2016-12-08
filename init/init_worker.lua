local router = require 'lib.router'
local lock = require 'resty.lock'
local monitor = require 'monitor'

function init_router()
    local mutex = lock:new('locks', {timeout = 0})
    local es, err = mutex:lock('init_router')
    if not es then
        ngx.log(ngx.NOTICE, ' init_router() called in another worker ')
        return
    end
    if err then
        ngx.log(ngx.ERR, err)
    end

    router.load_rules()
    router.load_upstream()

    mutex:unlock()
    ngx.log(ngx.NOTICE, 'all routes loaded')
end


-- can only use worker because cosocket is disabled
ngx.timer.at(0, init_router)
ngx.timer.at(0, monitor.monitor)
