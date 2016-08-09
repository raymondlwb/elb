local utils = require "utils"
local limit = require 'lib.filter.limit'


-- FIXME openresy 在 access 阶段如果 exit
-- 只有 [200, 300) 之间的 status code 可以正确退出
-- 其他 code 依然会继续执行 content 阶段的内容
-- 所以这里的 499 和 403 可能会需要改掉


-- check limits first
-- check request limit
local delay = limit.check_req_limit(ngx.var.host, ngx.var.uri)
if not delay then
    ngx.exit(ngx.HTTP_TOO_MANY_REQUESTS)
elseif delay > 0 then
    ngx.sleep(delay)
end


-- TODO check ip blacklist


-- 默认还是用host
-- e.g. www.ricebook.net
local key = ngx.var.host
local second_path = '/'
local first_path = ''
local domain_flag = true
-- 如果有path就尝试第一级path
-- 第一级path拼host上
-- e.g. www.ricebook.net/first_path

if ngx.var.uri ~= '/' then
    local path = utils.split(ngx.var.uri, '/', 2)
    first_path = path[2]
    key = key..'/'..first_path
    local sp = path[3]
    if sp then
        second_path =  second_path .. path[3]
    end
end

if ngx.var.host == 'enjoy.ricebook.com' or ngx.var.host ==  'enjoytest.ricebook.com' then
    domain_flag = false
    local fp, err = ngx.re.match(first_path, '(exhibit|order|trace|user|api|manger|invite)')
    if err ~= nil then
        ngx.log(ngx.ERR, err)
        ngx.exit(ngx.HTTP_BAD_GATEWAY)
    end
    if fp ~= nil then
        backend = 'eggsy_nova_web'
    else
        local ua = ngx.var.http_user_agent
        local ua_match, err = ngx.re.match(ua, '(iPhone|Android|BlackBerry|Mobi)')
        if err ~= nil then
            ngx.log(ngx.ERR, err)
            ngx.exit(ngx.HTTP_BAD_GATEWAY)
        end
        if ua_match ~= nil then
            if ngx.var.host == 'enjoy.ricebook.com' then
                backend = 'ysgge_nova_release'
            elseif ngx.var.host == 'enjoytest.ricebook.com' then
                backend = 'ysgge_intra_pre'
            end
        else
            backend = 'eggsy_nova_web'
        end
    end
end

-- check referrer
-- 为什么在这里检查呢, 因为要用这个 uri 啊
ngx.log(ngx.NOTICE, ngx.var.http_referer)
if not limit.check_referrer(key, ngx.var.http_referer) then
    ngx.exit(ngx.HTTP_FORBIDDEN)
end

if not backend then
   backend, _ = cache:get(key)
end
if not backend then
    -- 尝试用带path的去取
    -- cache key也带path
    -- 或者这里没有就还是原来的host
    local cache_key = key
    backend = utils.get_from_servernames(key)

    -- 如果取到了后端，就改写uri
    -- 比如
    -- www.ricebook.com/firstpath/secondpath?q=XXOO
    -- uri 应该变成 /secondpath
    if backend then
        ngx.req.set_uri(second_path)
    end

    -- 还是没有就用默认的host去取
    -- cache key变成默认的host
    if not backend then
        backend = utils.get_from_servernames(ngx.var.host)
        cache_key = ngx.var.host
    end

    -- 这就是真的没找到了
    -- 那就抛错吧
    if not backend then
        ngx.log(ngx.ERR, "no such backend")
        ngx.exit(ngx.HTTP_NOT_FOUND)
    end

    -- 即使没有命中也加上cache好了
    -- 不然容易拖死? 不至于吧...
    -- 60s ttl
    cache:set(cache_key, backend, 60)
else
    if second_path and domain_flag then
        ngx.req.set_uri(second_path)
    end
end

ngx.var.backend = backend
