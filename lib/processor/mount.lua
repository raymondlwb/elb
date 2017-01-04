-- local string = require 'string'
local _M = {}

function _M.process(conditions)
    for i = 1, #conditions, 1 do
        local mount_point = conditions[i]['condition']
        -- mount_point 如果没有以 / 开始或者结尾, 要加上
        -- 我们需要把 /mount_point/(.*) 给 rewrite 掉.
        -- if string.sub(mount_point, 1, 1) ~= '/' then
        --     mount_point = '/'..mount_point
        -- end
        -- if string.sub(mount_point, -1) ~= '/' then
        --     mount_point = mount_point..'/'
        -- end
        -- XXX 算了, 不处理了, 就是要求这么严格, 没写对不要怪ELB不rewrite.
        local uri, sub_time, err = ngx.re.sub(ngx.var.uri, '^'..mount_point..'(.*)$', '/$1', 'o')
        if err then
            ngx.log(ngx.ERR, "Error occurs : "..err.." while "..ngx.var.uri)
            return nil
        end
        if sub_time>0 then
            ngx.req.set_uri(uri)
            ngx.log(ngx.STDERR, conditions[i]['backend'])
            return conditions[i]['backend']
        end

        -- 如果没有一个match了
        if mount_point == 'jump' then
            return conditions[i]['backend']
        end
    end
    return nil
end

return _M
