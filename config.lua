local _M = {}

_M.REDIS_HOST = os.getenv("REDIS_HOST") or '127.0.0.1'
_M.REDIS_PORT = os.getenv("REDIS_PORT") or '6379'
_M.NAME = os.getenv("ELBNAME") or 'ELB'

_M.STATSD_HOST = os.getenv("STATSD") or '10.10.245.111'
_M.STATSD_PORT = os.getenv("STATSD_PORT") or 8125
_M.STATSD_FORMAT = 'elb3_domain_stat.%s.%s'

return _M
