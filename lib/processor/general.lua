local _M = {}

function _M.process(conditions)
    return conditions[1]['backend']
end

return _M
