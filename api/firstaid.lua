local dyups = require 'ngx.dyups'
local cjson = require 'cjson'
local rules = ngx.shared.rules
local utils = require 'utils'

local function update()
    local data = utils.read_data()
    local func = data['func']
    if func == 'RULE' then
        local succ, err, _ = rules:set(data['key'], cjson.encode(data['rule']))
        if not succ then
            utils.say_msg_and_exit(500, err)
        end
    end
    if func == 'UPSTREAM' then
        local servers = data['servers']
        local status, err = dyups.update(data['key'], servers)
        if status ~= ngx.HTTP_OK then
            utils.say_msg_and_exit(500, err)
        end
    end
    utils.say_msg_and_exit(200, 'ok')
end

local function delete()
    local data = utils.read_data()
    local func = data['func']
    if func == 'RULE' then
        rules:delete(data['key'])
    end
    if func == 'UPSTREAM' then
        dyups.delete(data['key'])
    end
    utils.say_msg_and_exit(200, 'ok')
end

if ngx.var.request_method == 'PUT' then
    update()
elseif ngx.var.request_method == 'DELETE' then
    delete()
end
