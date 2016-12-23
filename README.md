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
        'type': 'complex', # erulbpy 以这个为标识，对这种规则，erulbpy 都是直接 update 的
        'default': 'backend0',  # 默认的转发后端
        'rules_name' : ['rule0', 'rule1', 'rule2'], # 所有 rule 的集合, TODO: ELB 加上一个判断 rule 是否合法的检查
        'backends' : ['backend0', 'backend1', 'backend2'], # 所有 backend 的集合，ELB用来判断一个 backend 是 rule 还是 backends
        'init_rule': 'rule0', # 初始rule, ELB 会先从这个 rule 开始检查
        'rules': {
            'mount_point_rule': {
                'type': 'mount',
                'conditions': [
                    {'condition': '/hub/home/', 'backend': 'backend0'}, # 会把 /hub/home/xxxx rewrite 到 /xxxx, 后端拿到的 path 就是 /xxxx. 注意必须以 / 开头结尾.
                    {'condition': '/hub/fuck/', 'backend': 'backend1'}, # 会把 /hub/fuck/xxxx rewrite 到 /xxxx, 后端拿到的 path 就是 /xxxx. 注意必须以 / 开头结尾.
                    {'condition': '/hub/test/', 'backend': 'rule1'}, # 会把 /hub/test/xxxx rewrite 到 /xxxx, 后端拿到的 path 就是 /xxxx. 注意必须以 / 开头结尾.
                    {'condition': 'jump', 'backend': 'rule1'}, # 请求啥都不包含, 丢给下一个 (我对这个 jump 真的是有句fuck不知道该不该说...)
                ],
            },
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
* a simple example of mount point rules (python)

```
rule = {
        'default': 'ysgge___pre___intra',
        'rules_name': ['mount_point_rule'],
        'backends': ['ysgge___pre___intra'],
        'init_rule': 'mount_point_rule',
        'rules': {
            'mount_point_rule': {
                'type': 'mount',
                'conditions': [
                    {'condition': '/path/', backend: 'ysgge___pre___intra'}
                ]
            }
        }
}
```

* 更新 elb rule 的若干中情况

    elb 中转发规则的数据保存在 ngx.shared.rules(shared_dict) 中，以请求的 domain 为 key. 现在有两种 rule : general 和 mount， 这两种 rule 的主要区别在于： general rule 对应一个后端，mount point rule 对应多个后端。随着业务的发展，同一个域名可能会出现多种情况：原来只是对应一个后端的域名要增加挂载点；原来已经挂载了后端的域名要增加挂载点；而按照协议，citadel 会传来一个 rule 的 json 数据。所以现在的更新策略分成了6种不同的情况。以下这些逻辑已经被封装到 erulbpy 中。

1. 域名不存在，需要增加一个 general rule, 可以直接更新;

2. 域名不存在，需要增加一个 mount point rule;
    ```
    # citadel post 的数据
    domain = 'www.elb3test.org/home'
    rule = {
        'default': 'home___pre___intra',
        'rules_name': ['rule0'],
        'backends':['home___pre___intra'],
        'init_rule': 'rule0'
        'rules': {
            'rule0': {
                'type': 'general',
                'conditions': [
                    {'backend': 'home___pre___intra'}
                ]
            }
        }
    }
    # erulbpy 处理之后的数据
    domain = 'www.elb3test.org'
    rule = {
        'default': '',
        'rules_name': ['mount_point_rule'],
        'backends': ['home___pre___intra'],
        'init_rule': 'mount_point_rule',
        'rules': {
            'mount_point_rule': {
                'type': 'mount',
                'conditions': [
                    {'condition': '/home/', 'backend': 'home___pre___intra'},
                    {'condition': 'jump', 'backend': 'rule0'} # 哨兵位，方便实现代码
                ]
            },
            'rule0': {}
        }
    }
    ```

3. 域名存在一个 general rule , 需要变更为新的 general rule, 可以直接更新;

4. 域名存在一个 general rule , 需要变更为 mount point rule;
    ```
    # citadel post 的数据
    domain = 'www.elb3test.org/home'
    rule = {
        'default': 'home___pre___intra',
        'rules_name': ['rule0'],
        'backends':['home___pre___intra'],
        'init_rule': 'rule0'
        'rules': {
            'rule0': {
                'type': 'general',
                'conditions': [
                    {'backend': 'home___pre___intra'}
                ]
            }
        }
    }
    # redis 中的数据
    rule = {
        'default': 'ysgge___pre___intra',
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
    # erulbpy 处理之后的数据
    rule = {
        'default': 'ysgge___pre___intra',
        'rules_name': ['mount_point_rule','rule0'],
        'backends':['home___pre___intra','ysgge___pre___intra'],
        'init_rule': 'mount_point_rule'
        'rules': {
            'mount_point_rule': {
                'type': 'mount',
                'conditions': [
                    {'condition': '/home/', 'backend': 'home___pre___intra'},
                    {'condition': 'jump', 'backend': 'rule0'}
                ]
            },
            'rule0': {
                'type': 'general',
                'conditions': [
                    {'backend': 'ysgge___pre___intra'}
                ]
            }
        }
    }
    ```

5. 域名存在一个 mount point rule, 需要增加/替换 general rule;
    ```
    # citadel post 的数据
    domain = 'www.elb3test.org'
    rule = {
        'default': 'ysgge2___pre___intra',
        'rules_name': ['rule0'],
        'backends':['ysgge2___pre___intra'],
        'init_rule': 'rule0'
        'rules': {
            'rule0': {
                'type': 'general',
                'conditions': [
                    {'backend': 'ysgge2___pre___intra'}
                ]
            }
        }
    }
    # redis 中保存的数据, 这里其实要替换里面的 general 部分, 无论增加还是替换，都是可以的
    rule = {
        'default': 'ysgge___pre___intra',
        'rules_name': ['mount_point_rule','rule0'],
        'backends':['home___pre___intra','ysgge___pre___intra'],
        'init_rule': 'mount_point_rule'
        'rules': {
            'mount_point_rule': {
                'type': 'mount',
                'conditions': [
                    {'condition': '/home/', 'backend': 'home___pre___intra'},
                    {'condition': 'jump', 'backend': 'rule0'}
                ]
            },
            'rule0': {
                'type': 'general',
                'conditions': [
                    {'backend': 'ysgge___pre___intra'}
                ]
            }
        }
    }
    # erulbpy 处理自后的数据
    rule = {
        'default': 'ysgge___pre___intra2',
        'rules_name': ['mount_point_rule','rule0'],
        'backends':['home___pre___intra','ysgge2___pre___intra'],
        'init_rule': 'mount_point_rule'
        'rules': {
            'mount_point_rule': {
                'type': 'mount',
                'conditions': [
                    {'condition': '/home/', 'backend': 'home___pre___intra'},
                    {'condition': 'jump', 'backend': 'rule0'}
                ]
            },
            'rule0': {
                'type': 'general',
                'conditions': [
                    {'backend': 'ysgge2___pre___intra'}
                ]
            }
        }
    }
    ```

6. 域名存在一个 mount point rule, 需要增加新的 mount point rule;
    ```
    # citadel post 的数据
    domain = 'www.elb3test.org/product'
    rule = {
        'default': 'product___pre___intra',
        'rules_name': ['rule0'],
        'backends':['product___pre___intra'],
        'init_rule': 'rule0'
        'rules': {
            'rule0': {
                'type': 'general',
                'conditions': [
                    {'backend': 'product___pre___intra'}
                ]
            }
        }
    }
    # redis 中保存的数据
    rule = {
        'default': 'ysgge___pre___intra',
        'rules_name': ['mount_point_rule','rule0'],
        'backends':['home___pre___intra','ysgge___pre___intra'],
        'init_rule': 'mount_point_rule'
        'rules': {
            'mount_point_rule': {
                'type': 'mount',
                'conditions': [
                    {'condition': '/home/', 'backend': 'home___pre___intra'},
                    {'condition': 'jump', 'backend': 'rule0'}
                ]
            },
            'rule0': {
                'type': 'general',
                'conditions': [
                    {'backend': 'ysgge___pre___intra'}
                ]
            }
        }
    }
    # erulbpy 处理之后的数据, general 部分不会改变
    rule = {
        'default': 'ysgge___pre___intra',
        'rules_name': ['mount_point_rule','rule0'],
        'backends':['home___pre___intra', 'product___pre___intra', 'ysgge___pre___intra'],
        'init_rule': 'mount_point_rule'
        'rules': {
            'mount_point_rule': {
                'type': 'mount',
                'conditions': [
                    {'condition': '/home/', 'backend': 'home___pre___intra'},
                    {'condition': '/product/', 'backend': 'product___pre___intra'},
                    {'condition': 'jump', 'backend': 'rule0'}
                ]
            },
            'rule0': {
                'type': 'general',
                'conditions': [
                    {'backend': 'ysgge___pre___intra'}
                ]
            }
        }
    }
    ```

删除 rule 的原则分为两种情况：

1. 删除general rule: 删除对应的 general rule 部分
2. 删除挂载点: 删除对应的 mount point

每种情况 erulbpy 都会从 redis 中找到对应的记录，删掉对应的 backend, 如果对应的记录所有 backend 都删掉了, 则删掉对应的记录，否则更新记录.

    ```
    # 假设对应 www.elb3test.org 的记录如下
    # redis 中保存的数据
    rule = {
        'default': 'ysgge___pre___intra',
        'rules_name': ['mount_point_rule','rule0'],
        'backends':['home___pre___intra','ysgge___pre___intra'],
        'init_rule': 'mount_point_rule'
        'rules': {
            'mount_point_rule': {
                'type': 'mount',
                'conditions': [
                    {'condition': '/home/', 'backend': 'home___pre___intra'},
                    {'condition': 'jump', 'backend': 'rule0'}
                ]
            },
            'rule0': {
                'type': 'general',
                'conditions': [
                    {'backend': 'ysgge___pre___intra'}
                ]
            }
        }
    }

    # init ELBClient
    client = ELBClient(redis_url, elb_name)
    # 删去对应 /home/ 的挂载点
    client.delete_rule('www.elb3test.org/home')

    # 删去之后 redis 保存的数据变成
    rule = {
        'default': 'ysgge___pre___intra',
        'rules_name': ['rule0'],
        'backends':['ysgge___pre___intra'],
        'init_rule': 'rule0',
        'rules': {
            'rule0': {
                'type': 'general',
                'conditions': [
                    {'backend': 'ysgge___pre___intra'}
                ]
            }
        }

    # 删去 general rule
    client.delete_rule('www.elb3test.org')

    #删除之后 www.elb3test.org 对应的 rule 没有
    ```

处理像示例里面 complex rule 的情况：这个目前只能手动了，还没有想好怎样处理，而且目前只有一个域名有这个需求。真的实现了，估计要内嵌一个 DSL .

* erulbpy

erulbpy 是对外服务的 erulb api。
