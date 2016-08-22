local utils = require 'utils'

local _M = {}

function get_first_path()
    local path = utils.split(ngx.var.uri, '/', 2)
    return path[2]
end

function _M.process(conditions)
    local path = get_first_path()
    for i = 1, #conditions, 1 do
        key = conditions[i]['condition']
        if path == key then
            return conditions[i]['backend']
        end
    end
    return nil
end

return _M
