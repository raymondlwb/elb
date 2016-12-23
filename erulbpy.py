# -*- coding: utf-8 -*-

import logging
import json

from redis import Redis
from ruledata import UpdateRule

logger = logging.getLogger('erulbpy')

class PubsubOperations(object):
    UPDATE = '1'
    DELETE = '0'


class PubsubMessageType(object):
    UPSTREAM = 'UPSTREAM'
    RULE = 'RULE'


class ELBClient(object):

    def __init__(self, redis_url='redis://127.0.0.1:6379', name='testelb'):
        self.name = name
        self._upstream_key = '{}:upstream'.format(name)
        self._channel_key = '{}:upstream_and_rule'.format(name)
        self._rule_index_key = '{}:rules'.format(name)
        self.redis_url = redis_url
        self.rds = Redis.from_url(redis_url)

    def set_upstream(self, backend, servers):
        """
        backend -- str, nginx upstream name
        servers -- list of str, eash is a server address
        """
        if not servers:
            return self.delete_upstream(backend)
        nginx_server_clause = '\n'.join(['server {};'.format(server) for server in servers])
        self.rds.hset(self._upstream_key, backend, nginx_server_clause)
        logger.debug('Set ELB %s upstream %s: %s', self.name, backend, servers)
        msg = {
            'TYPE': PubsubMessageType.UPSTREAM,
            'OPER': PubsubOperations.UPDATE,
            'BACKEND': backend,
            'SERVERS': nginx_server_clause,
        }
        self.rds.publish(self._channel_key, json.dumps(msg))

    def get_upstream(self, backend):
        return self.rds.hget(self._upstream_key, backend)

    def delete_upstream(self, backend):
        logger.debug('Delete ELB %s upstream %s', self.name, backend)
        self.rds.hdel(self._upstream_key, backend)
        msg = {
            'TYPE': PubsubMessageType.UPSTREAM,
            'OPER': PubsubOperations.DELETE,
            'BACKEND': backend
        }
        self.rds.publish(self._channel_key, json.dumps(msg))

    def get_rule(self, domain):
        key = '{}:{}'.format(self.name, domain)
        rule_text = self.rds.get(key)
        return json.loads(rule_text)

    def set_rule(self, url, rule):
        """
        domain -- str
        rule -- ELB rule dict
        """
        rule_data = UpdateRule(url, rule, self.redis_url, self.name)
        domain, rule = rule_data.add_backend()
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

    def delete_rule(self, domains):
        """
        domains -- list of domain
        """
        if isinstance(domains, basestring):
            domains = domains,

        pipe = self.rds.pipeline()
        logger.debug('Delete ELB %s rule: %s', self.name, domains)
        for domain in domains:
            rule_data = UpdateRule(domain, None, self.redis_url, self.name)
            domain, rule = rule_data.del_backend()
            key = '{}:{}'.format(self.name, domain)
            if not rule: # 对应的 rule 没有 backend 了，可以把这个域名对应的数据删去
                msg = {
                    'TYPE': PubsubMessageType.RULE,
                    'OPER': PubsubOperations.DELETE,
                    'KEY': key
                }
                pipe.hdel(self._rule_index_key, key)
                pipe.delete(key)
                pipe.publish(self._channel_key, json.dumps(msg))
                continue

            encoded_rule = json.dumps(rule)
            msg = {
                'TYPE': PubsubMessageType.RULE,
                'OPER': PubsubOperations.UPDATE,
                'KEY': key,
                'RULE': encoded_rule,
            }
            pipe.set(key, encoded_rule)
            pipe.publish(self._channel_key, json.dumps(msg))

        pipe.execute()
