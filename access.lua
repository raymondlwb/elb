local utils = require 'utils'
local limit = require 'lib.filter.limit'
local config = require 'config'
local ruleprocess = require 'lib.rule'
local rules = ngx.shared.rules

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

-- rule就保存在shared.rules里面
-- 理论上来说redis里面有shared.rules里面也该有
-- 如果shared.rules没有而redis有，那就是出错了
-- 所以就不查redis了
local key = config.NAME .. ':' .. ngx.var.host
local rule = rules:get(key)
if rule == nil then
    ngx.log(ngx.ERR, 'Cannot get rule for ' .. key)
    ngx.exit(ngx.HTTP_NOT_FOUND)
end

backend = ruleprocess.process(rule)
if backend == nil then
    ngx.log(ngx.ERR, 'Cannot get backend for ' .. key)
    ngx.exit(ngx.HTTP_NOT_FOUND)
end

ngx.var.backend = backend
