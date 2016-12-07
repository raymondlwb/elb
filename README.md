Eru load balance
================

## Install

1. [Openresty](http://openresty.org)
2. [ngx_http_dyups_module](https://github.com/yzprofile/ngx_http_dyups_module)
3. `pip install -U git+http://gitlab.ricebook.net/platform/erulb3.git#egg=erulb-py -i https://pypi.doubanio.com/simple/`

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

* ELB 处理RULE的原则

    ELB 的 rule 是一个树状结构，当请求进来的时候，ELB 会先从 init_rule 开始，判断流量满足 rule 中哪个 condition. 当流量满足 rule 中的 condition 的时候，ELB 进入对应的 backend， 该 backend 可能是一个 dyups 中的 key（这个时候，我们拿到了真正的后端），也可能是下一级的 rule， 如果拿到了真正的后端，我们可以进入 proxy_pass 将流量转发到后端，如果拿到了下一级的 rule， 我们会进行新的 condition 判断。如果整个流程完成之后，我们无法获得一个真正的后端，流量转发到 default 对应的后端。

* a complex example of rules (python)

```
### 注意双单引号, 用`json.dumps` 将 json 序列化成一个符合标准的 json 字符串才是保险的。
rule = {
        'default': 'backend0',  # 默认的转发后端
        'rules_name' : ['rule0', 'rule1', 'rule2'], # 所有 rule 的集合, TODO: ELB 加上一个判断 rule 是否合法的检查
        'backends' : ['backend0', 'backend1', 'backend2'], # 所有 backend 的集合，ELB用来判断一个 backend 是 rule 还是 backends
        'init_rule': 'rule0', # 初始rule, ELB 会先从这个 rule 开始检查
        'rules': {
            'rule0': {
                'type': 'path',  # rule 的类型决定了后续判断的逻辑, path 会根据 uri 的第一级路径，比较字符串是否相等
                'conditions': [
                    {'condition':'test', 'backend':'backend0'},  # /test/blabla 的流量会到 backend0
                    {'condition':'prometheus', 'backend':'backend1'}, # /prometheus/blabla 的流量会到 backend1
                    {'condition':'user', 'backend':'rule1'}, # /user/blabla 的流量会到 rule1
                    {'condition':'jump', 'backend':'rule2'} # 如果对应的 path 没有定义，扔到rule2
                ]
            },
            'rule1': {
                'type': 'ua',
                'conditions': [
                    {'condition':'(iPhone)', 'backend':'backend0'}, # 如果 ua 包含 iPhone 那么扔到 backend0
                    {'condition':'(Android|Winodws)', 'backend':'backend1'} # 如果 ua 包含 Android|Windows 扔到 backend0
                ]
            },
            'rule2': {
                'type': 'general', # 这一种是最简单的 rule, 直接转发到对应的后端
                'conditions': [
                    {'backend':'backend2'}
                ]
            }

        }
    }
```

* a simple example of rules (python)

```
# 以 apitest.ricebook.com 的数据为例
rule = {
        'default': 'ysgge___pre___intra', # 这些字段还是也要加上
        'rules_name': ['rule0'],
        'backends':['ysgge___pre___intra'],
        'init_rule': 'rule0'
        'rules': {
            'rule0': {
                'type': 'general',
                'conditions': [
                    {'backend': 'ysgge___pre___intra'}
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

data = {
        'rule': rule, # defined above
        'domain': 'www.dante.org'
}
res = requests.put(query, data=json.dumps(data)) # if ok, res.content == {'msg':'ok'}

res = requests.get(query) # if ok, res.content will be a json contain all rules.

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
