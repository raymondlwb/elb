# -*- coding: utf-8 -*-

import logging
import json
import urlparse
from redis import Redis

logger = logging.getLogger('erulbpy')

class RuleData(object):
    RuleSameDomainNotExists = 0
    GeneralRuleSameDomainExists = 1
    MountRuleSameDomainExists = 2
    DEFAULT_MOUNT_RULE = {
        'default' : '',
        'rules_name': ['mount_point_rule'],
        'backends': [],
        'init_rule': 'mount_point_rule',
        'rules': {
            'mount_point_rule': {
                'type': 'mount',
                'conditions': [
                    {'condition': 'jump', 'backend': 'rule0'}
                ]
            },
            'rule0': {}
        }
    }

    def __init__(self, url, rule, redis_url='redis://127.0.0.1:6379', name='testelb'):
        self.type = 'mount' if '/' in url.strip('/') else 'general'
        parse_url = urlparse.urlparse('http//'+url)
        self.domain = parse_url.netloc
        self.path = parse_url.path
        self.rule = rule
        self.rds = Redis.from_url(redis_url)
        self.key = '{}:{}'.format(name, self.domain)

    def _check_rule_status(self):
        rule = self.rds.get(self.key)
        if not rule:
            return self.RuleSameDomainNotExists, None
        rds_rule = json.loads(rule)
        if 'mount_point_rule' in rds_rule:
            return self.MountRuleSameDomainExists, rds_rule
        return self.GeneralRuleSameDomainExists, rds_rule

    def _update_rule(self, status, redis_rule):
        if self.type == 'general':
            if status == self.RuleSameDomainNotExists or status == self.GeneralRuleSameDomainExists:
                return self.domain, self.rule
            return self.domain, self._update_general_into_mount(redis_rule)
        if self.type == 'mount':
            if status == self.RuleSameDomainNotExists:
                return self.domain, self._add_mount_rule()
            if status == self.GeneralRuleSameDomainExists:
                return self.domain, self._update_mount_into_general(redis_rule)
            return self.domain, self._update_mount_into_mount(redis_rule)

    def _update_general_into_mount(self, rds_rule):
        backend = self.rule['default']
        if 'rule0' not in rds_rule['rules_name']:
            rds_rule['rules_name'].append('rule0')
            rds_rule['backends'].append(backend)
        else:
            rds_rule['backends'][-1] = backend

        rds_rule['default'] = backend
        rds_rule['rules']['rule0'] = self.rule['rules']['rule0']
        return rds_rule

    def _add_mount_rule(self):
        backend = self.rule['default']
        self.DEFAULT_MOUNT_RULE['default'] = backend
        self.DEFAULT_MOUNT_RULE['backends'].append(backend)
        condition = self.path if self.path[-1] == '/' else (self.path + '/')
        self.DEFAULT_MOUNT_RULE['rules']['mount_point_rule']['conditions'].append({
            'condition': condition,
            'backend': backend,
        })
        return self.DEFAULT_MOUNT_RULE

    def _update_mount_into_mount(self, rds_rule):
        backend = self.rule['default']
        condition = self.path if self.path[-1] == '/' else (self.path + '/')
        rds_rule['rules']['mount_point_rule']['conditions'].insert(-1, {'condition': condition, 'backend': backend})
        return rds_rule

    def _update_mount_into_general(self, rds_rule):
        backend = self.rule['default']
        condition = self.path if self.path[-1] == '/' else (self.path + '/')
        rds_rule['init_rule'] = 'mount_point_rule'
        rds_rule['rules_name'].insert(0, 'mount_point_rule')
        rds_rule['backends'].insert(0, 'backend')
        rds_rule['rules']['mount_point_rule'] = {
            'type': 'mount',
            'conditions': [
                {'condition': condition, 'backend': backend},
                {'condition': 'jump', 'backend': 'rule0'}
            ]
        }
        return rds_rule

    def update_rule(self):
        """
        return:
        domain: domain without path
        rule: update rule -- add to a existing mount point rule or gerneral rule
        """
        status, rds_rule = self._check_rule_status()
        return self._update_rule(status, rds_rule)

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
        rule_data = RuleData(url, rule, self.redis_url, self.name)
        domain, rule = rule_data.update_rule()
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
            key = '{}:{}'.format(self.name, domain)
            msg = {
                'TYPE': PubsubMessageType.RULE,
                'OPER': PubsubOperations.DELETE,
                'KEY': key
            }
            pipe.hdel(self._rule_index_key, domain)
            pipe.delete(key)
            pipe.publish(self._channel_key, json.dumps(msg))

        pipe.execute()
