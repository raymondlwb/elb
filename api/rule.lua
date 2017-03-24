local cjson = require 'cjson'
local utils = require 'utils'
local lock = require 'resty.lock'
local router = require 'lib.router'

local function reload()
    local mutex = lock:new('locks', {timeout=0, exptime=3})
    local rlock, err = mutex:lock('reload_rule')
    if not rlock then
        utils.say_msg_and_exit(ngx.HTTP_OK, ' rule reload in another worker ')
    end
    if err then
        utils.say_msg_and_exit(ngx.HTTP_INTERNAL_SERVER_ERROR, err)
    end
    router.load_rules()
    mutex:unlock()
    utils.say_msg_and_exit(ngx.HTTP_OK, 'ok')
end

local function detail()
    local res = router.get_rule()
    utils.say_msg_and_exit(ngx.HTTP_OK, res)
end

if ngx.var.request_method == 'PUT' then
    reload()
elseif ngx.var.request_method == 'GET' then
    detail()
end
ngx.exit(ngx.HTTP_BAD_REQUEST)
