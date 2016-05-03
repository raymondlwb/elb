local utils = require "utils"

-- 默认还是用host
-- e.g. www.ricebook.net
local key = ngx.var.host

-- 如果有path就尝试第一级path
-- 第一级path拼host上
-- e.g. www.ricebook.net/first_path/
if ngx.var.uri ~= '/' then
    local first_path = utils.split(ngx.var.uri, '/', 2)[2]
    key = key..'/'..first_path..'/'
end

backend, _ = cache:get(key)
if not backend then
    -- 尝试用带path的去取
    -- cache key也带path
    -- 或者这里没有就还是原来的host
    local cache_key = key
    backend = utils.get_from_servernames(key)

    -- 还是没有就用默认的host去取
    -- cache key变成默认的host
    if not backend then
        backend = utils.get_from_servernames(ngx.var.host)
        cache_key = ngx.var.host
    end
    -- 即使没有命中也加上cache好了
    -- 不然容易拖死? 不至于吧...
    -- 60s ttl
    cache:set(cache_key, backend, 60)
end

ngx.var.backend = backend
