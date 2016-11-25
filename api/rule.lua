local cjson = require 'cjson'
local utils = require 'utils'
local router = require 'lib.router'

local function update()
    local data = utils.read_data()
    local domain = data['domain']
    local rule = cjson.encode(data['rule'])
    router.add_rule(domain, rule)
    utils.say_msg_and_exit(ngx.HTTP_OK, 'ok')
end

local function delete()
    local data = utils.read_data()
    local domains = data['domains']
    if type(domains) ~= 'table' then
        domains = {domains}
    end
    router.delete_rule(domains)
    utils.say_msg_and_exit(ngx.HTTP_OK, 'ok')
end

local function detail()
    local res = router.get_rule()
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
