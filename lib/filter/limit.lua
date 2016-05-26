local req = require 'lib.filter.req'
local utils = require 'utils'

local _M = {}

-- check request limit
-- if return 0, means check is passed
-- if return nil, means check is not passed, should reject this request
-- if return number greater than 0, means check is passed but we should wait delay seconds
function _M.check_req_limit(host, uri)
    local key = utils.make_filter_key(host, uri)
    if not key then
        return 0
    end

    local delay, err = reqlimit:incoming(key, true)
    if not delay and err == 'rejected' then
        return nil
    end

    return delay
end

function _M.check_user_agent(user_agent)
    return true
end

function _M.check_referrer(ref)
    return true
end

function _M.check_ip_blacklist(ip)
    return true
end

return _M
