local utils = require 'utils'
local router = require 'lib.router'
local lock = require 'resty.lock'

local function reload()
    local mutex = lock:new('locks', {timeout=0, exptime=3})
    local rlock, err = mutex:lock('reload_upstream')
    if not rlock then
        utils.say_msg_and_exit(ngx.HTTP_OK, ' upsteam reloaded in another worker ')
    end
    if err then
        utils.say_msg_and_exit(ngx.HTTP_INTERNAL_SERVER_ERROR, err)
    end
    router.load_upstream()
    mutex:unlock()
    utils.say_msg_and_exit(ngx.HTTP_OK, 'ok')
end

local function detail()
    local result, err = router.get_upstreams()
    if err then
        utils.say_msg_and_exit(ngx.HTTP_INTERNAL_SERVER_ERROR, err)
    end
    ngx.say(cjson.encode(result))
    ngx.exit(ngx.HTTP_OK)
end

if ngx.var.request_method == 'PUT' then
    reload()
elseif ngx.var.request_method == 'GET' then
    detail()
end
ngx.exit(ngx.HTTP_BAD_REQUEST)
