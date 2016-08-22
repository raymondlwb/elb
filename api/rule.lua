local utils = require 'utils'
local config = require 'config'
local cjson = require 'cjson'
local redis = require 'lib.redtool'
local lock = require 'resty.lock'

local name = config.NAME
local index_key = name .. ':rules'
local rules = ngx.shared.rules


local function update()
    local data = utils.read_data()
    local domain = data['domain']
    local rule = cjson.encode(data['rule'])
    local key = name .. ':' .. domain

    local mutex = lock:new('locks', {timeout=0, exptime=3})
    local rlock, err = mutex:lock('update')
    if not rlock then
        ngx.log(ngx.STDERR, err)
        utils.say_msg_and_exit(ngx.HTTP_OK, 'rule updated in another worker.')
    end
    if err then
        ngx.log(ngx.ERR, err)
        ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end
    local succ, err, _ = rules:set(key, rule)
    if not succ then
        utils.say_msg_and_exit(ngx.HTTP_OK, err)
    end

    local rds = redis:new()
    rds:hset(index_key, key, domain)
    rds:set(key, rule)
    utils.say_msg_and_exit(ngx.HTTP_OK, 'ok')
end

local function delete()
    local data = utils.read_data()
    local domain = data['domain']
    local rds = redis:new()
    local key = name .. ':' .. domain
    local mutex = lock:new('locks', {timeout=0})
    local rlock, err = mutex:lock('delete')
    if not rlock then
        utils.say_msg_and_exit(ngx.HTTP_OK, 'rule deleted in another worker.')
    end
    if err then
        utils.say_msg_and_exit(ngx.HTTP_INTERNAL_SERVER_ERROR, err)
    end

    rules:delete(key)
    rds:hdel(index_key, key)
    rds:del(key)
    utils.say_msg_and_exit(ngx.HTTP_OK, 'ok')
end

local function detail()
    res = {}
    local rule_records = rules:get_keys(0)
    for _, key in ipairs(rule_records) do
        res[key] = rules:get(key)
    end
    ngx.say(cjson.encode(res))
    ngx.exit(ngx.HTTP_OK)
end

if ngx.var.request_method == 'PUT' then
    update()
elseif ngx.var.request_method == 'DELETE' then
    delete()
elseif ngx.var.request_method == 'GET' then
    detail()
end
ngx.exit(ngx.HTTP_BAD_REQUEST)
