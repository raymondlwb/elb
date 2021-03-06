local utils = require 'utils'
local redis = require 'lib.redtool'
local cjson = require 'cjson'
local config = require 'config'
local key = config.NAME .. ':rules'

local result = {}
local rds = redis:new()
local domains = rds:hkeys(key)
if domains then
    result = domains
end
ngx.say(cjson.encode(result))
ngx.exit(ngx.HTTP_OK)
