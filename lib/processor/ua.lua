string = require 'string'
local _M = {}

-- TODO : 类似 path 这样的黑名单机制要怎样做啊。
--        现在 ua 分流只能作为最后的一级 rule 啊。

function _M.process(conditions)
    for i = 1, #conditions, 1 do
        key = conditions[i]['condition']
        if not  ngx.var.http_user_agent then
            ngx.log(ngx.ERR, "UA is nil")
            return nil
        end
        local ua = string.lower(ngx.var.http_user_agent)
        local captured, err = ngx.re.match(ua, key)
        if err ~= nil then
            ngx.log(ngx.ERR, "ngx.re.match failed: "..err)
            ngx.log(ngx.ERR, "Input UA: "..ua)
            return nil
        end
        if captured ~= nil then
            return conditions[i]['backend']
        end
        if key == 'jump' then
            return conditions[i]['backend']
        end
    end
    return nil
end

return _M
