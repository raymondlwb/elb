local config = require 'config'

local cost = 0
for token in string.gmatch(ngx.var.upstream_response_time, '[^,]+') do
    local time = tonumber(token)
    if time then
        cost = cost + time
    end
end

local host = ngx.var.host
-- statsd
local statsd_host = string.gsub(host, '%.', '_')
local statsd_status = string.format(config.STATSD_FORMAT, statsd_host, 'status')
local statsd_cost = string.format(config.STATSD_FORMAT, statsd_host, 'cost')
local statsd_total = string.format(config.STATSD_FORMAT, statsd_host, 'total')

statsd.count(statsd_total, 1)
statsd.count(statsd_status..'.'..ngx.var.upstream_status, 1)
if cost then
    statsd.time(statsd_cost, cost*1000) -- 毫秒
end

local function statsd_flush(premature)
    statsd.flush(ngx.socket.udp, config.STATSD_HOST, config.STATSD_PORT)
end

local ok, err = ngx.timer.at(0, statsd_flush)
if not ok then
    ngx.log(ngx.ERR, 'failed to create timer: ', err)
end

if ngx.var.backend == '' then
    ngx.log(ngx.ERR, 'invalid domain: ', ngx.var.host)
    return
end
