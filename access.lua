local utils = require 'utils'
local config = require 'config'
local ruleprocess = require 'lib.rule'
local rules = ngx.shared.rules

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
