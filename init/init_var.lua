local req = require 'lib.filter.req'
local lrucache = require 'resty.lrucache'


cjson = require 'cjson'
cache = lrucache.new(200)
reqlimit = req.new('filter_indicator', 'filter_storage')


if not cache then
    ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
end
