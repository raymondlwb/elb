string = require 'string'
local _M = {}

function _M.process(conditions)
    for i = 1, #conditions, 1 do
        key = conditions[i]['condition']
        if not  ngx.var.http_user_agent then
            ngx.log(ngx.ERR, "ua is nil")
            return nil
        end
        local ua = string.lower(ngx.var.http_user_agent)
        local captured, err = ngx.re.match(ua, key)
        if err ~= nil then
            ngx.log(ngx.ERR, "ngx.re.match failed: "..err)
            ngx.log(ngx.ERR, "input ua: "..ua)
            return nil
        end
        if captured ~= nil then
            return conditions[i]['backend']
        end
    end
    return nil
end

return _M
