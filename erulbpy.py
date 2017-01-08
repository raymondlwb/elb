# -*- coding: utf-8 -*-
import json
import logging

import requests
from urlparse import urlparse
from redis import Redis, ConnectionError
from ruledata import UpdateRule


logger = logging.getLogger('erulbpy')

class ApiResult(object):
    SUCCESS = True
    FAIL = False

class PubsubOperations(object):
    UPDATE = '1'
    DELETE = '0'


class PubsubMessageType(object):
    UPSTREAM = 'UPSTREAM'
    RULE = 'RULE'


class ELBClient(object):

    def __init__(self, redis_url='redis://127.0.0.1:6379', name='testelb', elb_urls='127.0.0.1'):
        self.name = name
        self._upstream_key = '{}:upstream'.format(name)
        self._channel_key = '{}:upstream_and_rule'.format(name)
        self._rule_index_key = '{}:rules'.format(name)
        self.redis_url = redis_url
        self.rds = Redis.from_url(redis_url)
        self.rule_key = '{}:rules'.format(name)
        self.upstream_key = '{}:upstream'.format(name)
        self.rds_alive = True

        if isinstance(elb_urls, basestring):
            elb_urls = [elb_urls]

        self.elb_urls = ['http://'+s if not urlparse(s).scheme else s for s in elb_urls]

    def dump_redis(self, elb_urls):
        """
        elb_urls: elb whose data need to dump into redis

        If redis crashed/flushed, use this api to dump data
        back to redis. Usually, dump data of one elb is enough.
        Let citadel choose which one to dump.
        """
        if isinstance(elb_urls, basestring):
            elb_urls = [elb_urls]

        pipe = self.rds.pipeline()
        for elb in elb_urls:
            upstreams = requests.get(elb + '/__erulb__/upstream').json()
            rules = requests.get(elb + '/__erulb__/rule').json()

            for key in rules:
                pipe.set(key, rules[key])
                pipe.hset(self.rule_key, key, key.split(':')[1])

            for key in upstreams:
                data = upstreams[key]
                ips = [s['addr'] for s in data]
                servers = ['server {};'.format(ip) for ip in ips]
                value = '\n'.join(servers)
                pipe.hset(self.upstream_key, key, value)

        try:
            pipe.execute()
        except ConnectionError as e:
            raise e

    def reload(self, elb_urls):
        """
        elb_urls: elb whose data need to reload

        If there is elb whose data is inconsistent with redis,
        use this api to reload, citadel should decide which elb
        to reload.
        """
        if not isinstance(elb_urls, basestring):
            elb_urls = [elb_urls]

        for elb in elb_urls:
            upstream_res = requests.put(elb + '/__erulb__/upstream')
            rule_res = requests.put(elb + '/__erulb__/rule')

        return upstream_res.status_code == 200 and rule_res.status_code == 200

    def _redis_set_upstream(self, backend, clause):
        self.rds.hset(self._upstream_key, backend, clause)
        logger.debug('Set ELB %s upstream %s: %s', self.name, backend, clause)
        msg = {
            'TYPE': PubsubMessageType.UPSTREAM,
            'OPER': PubsubOperations.UPDATE,
            'BACKEND': backend,
            'SERVERS': clause,
        }
        self.rds.publish(self._channel_key, json.dumps(msg))
        return ApiResult.SUCCESS, None

    def _http_set_upstream(self, backend, clause):
        """
        this api is used when redis is down.
        """
        data = {
            'key': backend,
            'func': 'UPSTREAM',
            'servers': clause,
        }

        api_res = ApiResult.SUCCESS
        fail_msg = {}
        for elb in self.elb_urls:
            res = requests.put(elb + '/__erulb__/firstaid', data=json.dumps(data))
            if res.status_code != 200:
                logger.error('err occurs: {}'.format(res.content))
                api_res = ApiResult.FAIL
                fail_msg[elb] = res.status_code

        return api_res, fail_msg

    def set_upstream(self, backend, servers):
        """
        backend -- str, nginx upstream name
        servers -- list of str, eash is a server address
        """
        if not servers:
            return self.delete_upstream(backend)

        nginx_server_clause = '\n'.join(['server {};'.format(server) for server in servers])
        try:
            return self._redis_set_upstream(backend, nginx_server_clause)
        except ConnectionError:
            return self._http_set_upstream(backend, nginx_server_clause)

    def get_upstream(self, backend):
        return self.rds.hget(self._upstream_key, backend)

    def _redis_del_upstream(self, backend):
        logger.debug('Delete ELB %s upstream %s', self.name, backend)
        self.rds.hdel(self._upstream_key, backend)
        msg = {
            'TYPE': PubsubMessageType.UPSTREAM,
            'OPER': PubsubOperations.DELETE,
            'BACKEND': backend
        }
        self.rds.publish(self._channel_key, json.dumps(msg))
        return ApiResult.SUCCESS, None

    def _http_del_upstream(self, backend):
        data = {
            'key': backend,
            'func': 'UPSTREAM',
        }

        api_res = ApiResult.SUCCESS
        fail_msg = {}
        for elb in self.elb_urls:
            res = requests.delete(elb + '/__erulb__/firstaid', data=json.dumps(data))
            if res.status_code != 200:
                logger.error('err occurs: {}'.format(res.content))
                api_res = ApiResult.FAIL
                fail_msg[elb] = res.status_code

        return api_res, fail_msg

    def delete_upstream(self, backend):
        try:
            return self._redis_del_upstream(backend)
        except ConnectionError:
            return self._http_del_upstream(backend)

    def get_rule(self, domain):
        key = '{}:{}'.format(self.name, domain)
        rule_text = self.rds.get(key)
        return rule_text and json.loads(rule_text)

    def _redis_set_rule(self, domain, rule):
        key = '{}:{}'.format(self.name, domain)
        logger.debug('Set ELB %s rule %s: %s', self.name, key, rule)
        self.rds.hset(self._rule_index_key, key, domain)
        encoded_rule = json.dumps(rule)
        self.rds.set(key, encoded_rule)
        msg = {
            'TYPE': PubsubMessageType.RULE,
            'OPER': PubsubOperations.UPDATE,
            'KEY': key,
            'RULE': encoded_rule,
        }
        self.rds.publish(self._channel_key, json.dumps(msg))
        return ApiResult.SUCCESS, None

    def _http_set_rule(self, domain, rule):
        key = '{}:{}'.format(self.name, domain)
        data = {
            'func': 'RULE',
            'key': key,
            'rule': rule,
        }

        api_res = ApiResult.SUCCESS
        fail_msg = {}
        for elb in self.elb_urls:
            res = requests.put(elb + '/__erulb__/firstaid', data=json.dumps(data))
            if res.status_code != 200:
                logger.error('err occurs: {}'.format(res.content))
                api_res = ApiResult.FAIL
                fail_msg[elb] = res.status_code

        return api_res, fail_msg

    def _redis_del_rule(self, domain):
        key = '{}:{}'.format(self.name, domain)
        logger.debug('Del ELB %s rule %s', self.name, key)
        msg = {
            'TYPE': PubsubMessageType.RULE,
            'OPER': PubsubOperations.DELETE,
            'KEY': key,
        }
        self.rds.hdel(self._rule_index_key, key)
        self.rds.delete(key)
        self.rds.publish(self._channel_key, json.dumps(msg))
        return ApiResult.SUCCESS, None

    def _http_del_rule(self, domain):
        key = '{}:{}'.format(self.name, domain)
        data = {
            'func': 'RULE',
            'key': key,
        }

        api_res = ApiResult.SUCCESS
        fail_msg = {}
        for elb in self.elb_urls:
            res = requests.delete(elb + '/__erulb__/firstaid', data=json.dumps(data))
            if res.status_code != 200:
                logger.error('err occurs: {}'.format(res.content))
                api_res = ApiResult.FAIL
                fail_msg[elb] = res.status_code

        return api_res

    def _set_rule(self, domain, rule):
        try:
            return self._redis_set_rule(domain, rule)
        except ConnectionError:
            return self._http_set_rule(domain, rule)

    def set_rule(self, url, rule):
        """
        domain -- str
        rule -- ELB rule dict
        """
        rule_data = UpdateRule(url, rule, self.redis_url, self.name, self.elb_urls[0])
        domain, rule = rule_data.add_backend()
        return self._set_rule(domain, rule)

    def _del_rule(self, domain):
        try:
            return self._redis_del_rule(domain)
        except ConnectionError:
            return self._http_del_rule(domain)

    def delete_rule(self, domains):
        """
        domains -- list of domain
        """
        if isinstance(domains, basestring):
            domains = domains,

        logger.debug('Delete ELB %s rule: %s', self.name, domains)

        api_res = ApiResult.SUCCESS
        for domain in domains:
            rule_data = UpdateRule(domain, None, self.redis_url, self.name, self.elb_urls[0])
            domain, rule = rule_data.del_backend()
            if not rule:  # 对应的 rule 没有 backend 了，可以把这个域名对应的数据删去
                if not self._del_rule(domain):
                    api_res = ApiResult.FAIL
                continue

            if not self._set_rule(domain, rule):
                api_res = ApiResult.FAIL

        return api_res
