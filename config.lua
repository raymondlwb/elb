local _M = {}

_M.REDIS_HOST = os.getenv("REDIS_HOST") or '127.0.0.1'
_M.REDIS_PORT = os.getenv("REDIS_PORT") or '6379'
_M.NAME = os.getenv('ELBNAME') or 'ELB'

return _M
