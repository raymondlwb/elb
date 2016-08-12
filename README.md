Eru load balance
================

## Install

1. [Openresty](http://openresty.org)
2. [ngx_http_dyups_module](https://github.com/yzprofile/ngx_http_dyups_module)

## Performance

ab test eru-agent debug pprof API

10K requests and 100 concurrency

Direct: 11904.49 requests / sec (by 24 core)
Proxy: 8100 requests / sec (by 8 core config)

## Feature

1. Dynamically add/remove/update backend (by ngx_http_dyups_module, part of [tengine](http://tengine.taobao.org/)).
2. Use redis to set servernames.
3. Calcuate upstream status (total response, avg response time, response code count).

## Configuration

1. Modify config.lua to set redis host and port.
2. Install openresty with ngx_http_dyups_module.
3. Copy and modify conf/dev.conf as you wish.
4. Start and enjoy.

## Rules
* How to define a rule

设计新的ELB的时候，考虑了以下的需求：

1. 同一个域名，不同的path对应不同的app；
2. 根据ua等request的条件，将流量打到版本不同的容器中；
3. 通过简单规则的组合创建更复杂的规则；

TBC

* an example of rules (python)
```
rule = {
        'default': 'default',
        'rules_name' : ['rule0', 'rule1'],
        'backends' : ['default', 'backend0', 'backend1'],
        'init_rule': 'rule0',
        'rules': {
            'rule0': {
                'type': 'path',
                'conditions': [
                    {'condition':'test', 'backend':'backend0'},
                    {'condition':'prometheus', 'backend':'backend1'},
                    {'condition':'(rule)', 'backend':'rule1'}
                ]
            },
            'rule1': {
                'type': 'ua',
                'conditions': [
                    {'condition':'(iPhone)', 'backend':'backend0'},
                    {'condition':'(Android|Winodws)', 'backend':'backend1'}
                ]
            }
        }
    }
```
* rules api
```
/__eru__/rule
PUT     :   增加规则
DELETE  :   删除规则
GET     :   查询规则
```
* api example (python)
```
import requests
import json

query = 'http://elb_host/__erulb__/rule

# add rule
data = {
        'rule': rule, # defined above
        'domain': 'www.dante.org'
}
res = requests.put(query, data=json.dumps(data)) # if ok, res.content == {'msg':'ok'}

# query rule
res = requests.get(query) # if ok, res.content will be a json contain all rules.

# delete rule
domain = 'www.dante.org'
res = requests.delete(domain)  # if ok, res.content == {'msg':'ok'}
```

## other API
* domain api
```
/__eru__/domain
GET : 取得ELB所有domain
```
备注: 和以前的设计不一样，现在`domain`跟`backend`的对应关系是由`rules`决定，而且`domain`会对应多个`backend`，所以只保留一个查询接口方便看ELB上管理了哪些`domain`.

* upstream api
```
/__eru__/upstream
GET : 取得ELB上所有的upstream
DELETE : 删除某一组upstream
PUT : 增加upstream
```
