local _M = {}

_M.REDIS_HOST = os.getenv("REDIS_HOST") or '127.0.0.1'
_M.REDIS_PORT = os.getenv("REDIS_PORT") or '6379'
_M.NAME = os.getenv("ELBNAME") or 'ELB'

_M.STATSD_HOST = os.getenv("STATSD_HOST") or 'localhost'
_M.STATSD_PORT = os.getenv("STATSD_PORT") or 8125
_M.STATSD_FORMAT = 'elb3_domain_stat.%s.%s'

_M.UPDATE = '1'
_M.DELETE = '0'
_M.UPSTREAM_KEY = _M.NAME .. ':upstream'
_M.CHANNEL_KEY = _M.NAME .. ':upstream_and_rule'

_M.REDIS_RECONNECT_INTERVAL = 1
_M.REDIS_RECONNECT_INTERVAL_UPPER = 20
return _M
