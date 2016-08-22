local _M = {}

local json = require 'cjson'
local redis = require 'lib.redtool'
local config = require 'config'
local ua_processor = require 'lib.processor.ua'
local path_processor = require 'lib.processor.path'
local general_processor = require 'lib.processor.general'
local rule_records = ngx.shared.rules

local processors = {
    ua = ua_processor,
    path = path_processor,
    general = general_processor
}

function one_of_backend(name, backends)
    for i = 1, #backends, 1 do
        if name == backends[i] then
            return true
        end
    end
    return false
end

function _M.process(rule_content)
    local rule_json = json.decode(rule_content)
    local rules_name = rule_json['rules_name']
    local backends = rule_json['backends']
    local result = rule_json.default
    local init_rule = rule_json['init_rule']

    local r = rule_json['rules'][init_rule]
    local is_backend = false

    while not is_backend do
        processor = processors[r['type']]
        res = processor.process(r['conditions'])
        if res == nil then
            break
        end
        if one_of_backend(res, backends) then
            is_backend = true
        else
            r = rule_json['rules'][res]
        end
    end

    if is_backend then
        result = res
    end
    return result
end

function _M.load_rules()
    local index_name = config.NAME .. ':rules'
    local rds = redis:new()
    local rs, err = rds:hgetall(index_name)
    if err then
        ngx.log(ngx.ERR, err)
        return
    end
    for i = 1, #rs, 2 do
        key = rs[i]
        rule = rds:get(rs[i])
        if rule then
            rule_records:add(key, rule)
        end
    end
end

return _M
