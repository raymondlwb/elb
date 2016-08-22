local _M = {}

function _M.process(conditions)
    for i = 1, #conditions, 1 do
        key = conditions[i]['condition']
        local captured, err = ngx.re.match(ngx.var.http_user_agent, key)
        if err ~= nil then
            return nil
        end
        if captured ~= nil then
            return conditions[i]['backend']
        end
    end
    return nil
end

return _M
