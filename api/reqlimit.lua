local utils = require 'utils'

-- add / update rules
-- {
--     "path1": rate1,
--     "path2": rate2,
-- }
local function add_or_update_rule()
    local data = utils.read_data()
    for path, rate in pairs(data) do
        reqlimit:add_or_update_rule(path, rate, rate * 1.2)
    end
    ngx.say(cjson.encode({msg = 'ok'}))
    ngx.exit(ngx.HTTP_OK)
end


-- delete rule
-- {"path": "path1"}
local function delete_rule()
    local data = utils.read_data()
    reqlimit:delete_rule(data['path'])
    ngx.say(cjson.encode({msg = 'ok'}))
    ngx.exit(ngx.HTTP_OK)
end


-- get all rules
local function get()
    local result = reqlimit:all_rules()
    ngx.say(cjson.encode(result))
    ngx.exit(ngx.HTTP_OK)
end


if ngx.var.request_method == 'PUT' then
    add_or_update_rule()
elseif ngx.var.request_method == 'DELETE' then
    delete_rule()
elseif ngx.var.request_method == 'GET' then
    get()
end
ngx.exit(ngx.HTTP_BAD_REQUEST)
