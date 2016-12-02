local utils = require 'utils'
local router = require 'lib.router'
local dyups = require 'ngx.dyups'

local function update()
    local data = utils.read_data()
    local backend = data['backend']
    if not backend then
        ngx.exit(ngx.HTTP_BAD_REQUEST)
    end
    local servers = table.concat(data['servers'])
    -- 接口只需要更新 redis 数据
    router.add_upstream(backend, servers)
    ngx.say(cjson.encode({msg = 'ok'}))
    ngx.exit(ngx.HTTP_OK)
end

local function delete()
    local data = utils.read_data()
    local backend = data['backend']
    if not backend then
        ngx.exit(ngx.HTTP_BAD_REQUEST)
    end
    router.delete_upstream(backend)
    ngx.say(cjson.encode({msg = 'ok'}))
    ngx.exit(ngx.HTTP_OK)
end

local function detail()
    local upstream = require 'ngx.upstream'
    local get_servers = upstream.get_servers
    local get_upstreams = upstream.get_upstreams
    local us = get_upstreams()
    local result = {}
    for _, u in ipairs(us) do
        local srvs, err = get_servers(u)
        if not srvs then
            ngx.log(ngx.ERR, 'failed to get servers in upstream ', u)
        else
            result[u] = srvs
        end
    end
    ngx.say(cjson.encode(result))
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
