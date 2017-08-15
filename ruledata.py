# -*- coding: utf-8 -*-
import json

import requests
from redis import Redis, ConnectionError
from six.moves.urllib_parse import urlparse


MOUNT_POINT_RULE = 'mount_point_rule'
RULE0 = 'rule0'


class RuleData(object):
    """
    封装了 rule data 的基本操作
    rule 由两部分组成:
    1. mount_point: 对应多个 backend;
    2. general rule(rule0): 对应一个 backend;
    考虑 rule data 的复杂性，我们对 rule 作出一些限制：
    1. 一条有效的 rule 必须有一个 backend;
    2. general rule(rule0) 部分可以没有 backend ; 若有，它的 backend 在 backends 里面最后一个;
    若没有，它的 default 为 '';
    3. rules_name 里面最多只有两个值：mount_point_rule, rule0。
    哪一个有对应的 backend 就加到 rules_names 里面；
    4. 根据3, 若 rules_name 为空，这个 rule 失效，可以删除对应的 domain;
    """

    def __init__(self, rule):
        self.rule = rule

    def set_general_rule(self, backend):
        """
        设置 general rule : 这个操作是幂等的
        """
        self.rule['default'] = backend
        if not self.rule['init_rule']:
            self.rule['init_rule'] = RULE0

        if RULE0 not in self.rule['rules_name']:
            self.rule['rules_name'].append(RULE0)
            self.rule['backends'].append(backend)
            self.rule['rules'][RULE0] = {
                'type': 'general',
                'conditions': [{'backend': backend}],
            }
            return self.rule

        self.rule['backends'][-1] = backend
        self.rule['rules'][RULE0]['conditions'][0]['backend'] = backend
        return self.rule

    def del_general_rule(self):
        """
        删去一个 rule 中的 general rule
        """
        self.rule['rules_name'].pop()
        # 如果删掉这个 general rule 之后
        # 整个 rule 为空，那么直接删掉整个 rule 好了
        if not self.rule['rules_name']:
            return None

        self.rule['default'] = ''
        self.rule['backends'].pop()
        self.rule['rules'].pop(RULE0)
        return self.rule

    def _del_mount_condition(self, path):
        self.rule['rules'][MOUNT_POINT_RULE]['conditions'] = [
            s for s in self.rule['rules'][MOUNT_POINT_RULE]['conditions']
            if s['condition'] != path]

    def _check_backend_with_same_name(self, backend):
        for _, rule in self.rule['rules'].items():
            for condition in rule['conditions']:
                if backend == condition['backend']:
                    return True
        return False

    def _get_mount_backend(self, path):
        return [s['backend'] for s in self.rule['rules'][MOUNT_POINT_RULE]['conditions']
                if s['condition'] == path]

    def add_mount_point(self, path, backend):
        """
        增加一个挂载点
        """
        if backend not in self.rule['backends']:
            self.rule['backends'].insert(-1, backend)

        self.rule['init_rule'] = MOUNT_POINT_RULE
        if MOUNT_POINT_RULE not in self.rule['rules_name']:
            self.rule['rules_name'].insert(0, 'mount_point_rule')
            self.rule['rules'][MOUNT_POINT_RULE] = {
                'type': 'mount',
                'conditions': [
                    {'condition': path, 'backend': backend},
                    {'condition': 'jump', 'backend': 'rule0'}
                ]
            }
            return self.rule

        paths = [s['condition'] for s
                 in self.rule['rules'][MOUNT_POINT_RULE]['conditions']]
        if path in paths:
            self._del_mount_condition(path)

        self.rule['rules'][MOUNT_POINT_RULE]['conditions'].insert(-1, {
            'condition': path, 'backend': backend})
        return self.rule

    def del_mount_point(self, path):
        """
        删除一个挂载点。
        如果删除这个挂载点之后没有别的 backend 了，那么可以删除整条 rule
        如果删除之歌挂载点之后，没有别的挂载点但是有 general 的 backend，
        那么要把 init_rule 等改回来
        """
        backend = self._get_mount_backend(path)
        if not backend:
            return self.rule

        self._del_mount_condition(path)
        if len(self.rule['rules'][MOUNT_POINT_RULE]['conditions']) == 1:
            self.rule['rules_name'].remove(MOUNT_POINT_RULE)
            self.rule['rules'].pop(MOUNT_POINT_RULE)
            self.rule['init_rule'] = 'rule0'

        # 一种糟糕的情况是不同的 mount-point 挂了同样的 backend
        # 所以需要检查有没有别的 rule 里面有 condition 对应这个 backend
        if not self._check_backend_with_same_name(backend[0]):
            try:
                self.rule['backends'].remove(backend[0])
            except ValueError:
                pass # 没脾气了，出现了数据错误，先这样救急吧

        if not self.rule['backends']:
            return None

        return self.rule


RULE_TEMPLATE = {
    'default': '',
    'rules_name': [],
    'backends': [],
    'init_rule': '',
    'rules': {}
}


class UpdateRule(object):

    RULE_NOT_EXISTS = 0
    MOUNT_POINT_RULE_EXISTS = 1
    GENERAL_RULE_EXISTS = 2

    def __init__(self, url, rule, redis_url, name, elb_instance_url):
        """
        url: 形如 www.elb3test.org 或 www.elb3test.org/path/xxx ;
        rule: citedal 传过来的 rule , del backend 的时候 rule 为 None ;
        redis_url: 因为需要查对应的域名是否有记录，所以需要查 redis ;
        name: the name of elb cluster
        """
        parsed_url = urlparse('//' + url.strip('/'), scheme='')
        self.domain = parsed_url.netloc
        self.path = parsed_url.path + '/' if parsed_url.path else None
        self.rule_to_update = rule
        self.rds = Redis.from_url(redis_url)
        self.key = '{}:{}'.format(name, self.domain)
        self.rule_online = None
        rule_api = elb_instance_url + '/__erulb__/rule'
        self.status = self._check_rule_record(rule_api)

    def _get_rule_data_online(self, api, key):
        data = requests.get(api).json()
        return data[key] if key in data else None

    def _check_rule_record(self, api):
        """
        检查是否存在对应 self.key 的数据，若存在，
        判断这个 rule 是否有挂载点.
        如果 redis 不可用，就用 elb 接口上的数据，
        """
        try:
            res = self.rds.get(self.key)
        except ConnectionError:
            res = self._get_rule_data_online(api, self.key)

        if not res:
            return self.RULE_NOT_EXISTS

        self.rule_online = json.loads(res)
        if MOUNT_POINT_RULE in self.rule_online['rules_name']:
            return self.MOUNT_POINT_RULE_EXISTS

        return self.GENERAL_RULE_EXISTS

    def add_backend(self):
        """
        为一个 url 增加一个 backend，
        包括6种情况，详情见 README
        """
        # 考虑 enjoy.ricebook.com 这种特别情况
        if 'type' in self.rule_to_update and self.rule_to_update['type'] == 'complex':
            return self.domain, self.rule_to_update

        # 情况1,3不需要改动传进来的 rule
        if not self.path and self.status != self.MOUNT_POINT_RULE_EXISTS:
            return self.domain, self.rule_to_update

        # 情况2, 域名不存在, 要增加 mount point
        if self.path and self.status == self.RULE_NOT_EXISTS:
            rule_data = RuleData(RULE_TEMPLATE)
            return self.domain, rule_data.add_mount_point(self.path,
                                                          self.rule_to_update['default'])

        # 情况4,6: 域名已经存在对应的 rule, 要增加 mount point
        if self.path and self.status != self.RULE_NOT_EXISTS:
            rule_data = RuleData(self.rule_online)
            return self.domain, rule_data.add_mount_point(self.path,
                                                          self.rule_to_update['default'])

        # 情况5, 域名存在 mount point，要 update rule0
        if not self.path and self.status == self.MOUNT_POINT_RULE_EXISTS:
            rule_data = RuleData(self.rule_online)
            return self.domain, rule_data.set_general_rule(self.rule_to_update['default'])

    def del_backend(self):
        """
        一个 domain 会对应多个 backend，所以删除 backend 的时候
        要检查 rule 是否还有 backend, 若没有，删除 domain 数据
        若有，只是更新对应的数据。
        """
        if self.status == self.RULE_NOT_EXISTS:
            return self.domain, None

        if 'type' in self.rule_online and self.rule_online['type'] == 'complex':
            return self.domain, None

        rule_data = RuleData(self.rule_online)
        if self.path:
            return self.domain, rule_data.del_mount_point(self.path)

        return self.domain, rule_data.del_general_rule()
