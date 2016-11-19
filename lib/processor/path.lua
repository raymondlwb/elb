local utils = require 'utils'
local string = require 'string'

local _M = {}

function get_first_path()
    local path = utils.split(ngx.var.uri, '/', 2)
    return path[2]
end

function _M.process(conditions)
    local path = get_first_path()
    for i = 1, #conditions, 1 do
        keys = conditions[i]['condition']
        for token in string.gmatch(keys, "[^,]+") do
            if path == token then
                ngx.log(ngx.ERR, "black list, jump to "..conditions[i]['backend'])
                return conditions[i]['backend']
            end
        end

        -- 如果我们指定了几个 path, 比如 /login
        -- 而除了这些 path 之外，我们还有第二层的规则
        -- 那么我们就直接跳走就好
        if keys == 'jump' then
            ngx.log(ngx.ERR, "white list, jump to "..conditions[i]['backend'])
            return conditions[i]['backend']
        end
    end
    return nil
end

return _M
