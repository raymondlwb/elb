local req = require 'lib.filter.req'
local ref = require 'lib.filter.ref'
local lrucache = require 'resty.lrucache'


cjson = require 'cjson'
cache = lrucache.new(200)
reqlimit = req.new('filter_indicator', 'filter_storage')
refcheck = ref.new('ref_storage')
statsd = require 'lib.statsd'

if not cache then
    ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
end
