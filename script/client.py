#!/usr/bin/env python
# -*- coding: utf-8 -*-

import os

import click
from redis import Redis

from erulbpy import ELBClient


ELBNAME = os.getenv('ELBNAME', 'ELB')

REDIS_HOST = os.getenv('REDIS_HOST', '127.0.0.1:6379')
ELB_URL = os.getenv('ELB_URL', 'http://127.0.0.1')
UPSTREAM_API = '/__erulb__/upstream'
RULE_API = '/__erulb__/rule'

ELB = ELBClient(REDIS_HOST, ELBNAME)

RULE = {
    "rules_name": ["rule0"],
    "rules": {
        "rule0": {
            "type": "general",
        }
    },
    "init_rule": "rule0",
    "default": ""
}

complex_rule = {
    'type': 'complex',
    'backends': ['eggsy___web___release', 'ysgge___release___release'],
    'default': 'eggsy___web___release',
    'init_rule': 'rule0',
    'rules': {'rule0': {'conditions': [{'backend': 'eggsy___web___release',
                                        'condition': 'exhibit,order,trace,user,api,manger,invite,topic,coupon,pay,apple-app-site-association,app'},
                                       {'backend': 'rule1', 'condition': 'jump'}],
                        'type': 'path'},
              'rule1': {'conditions': [{'backend': 'ysgge___release___release',
                                        'condition': '(iphone|android|blackberry|mobi)'}],
                        'type': 'ua'}},
    'rules_name': ['rule0', 'rule1']
}


@click.group()
@click.pass_context
def cli(ctx):
    ctx.obj['ELB'] = ELB
    ctx.obj['ELB_URL'] = ELB_URL
    ctx.obj['REDIS'] = Redis.from_url(REDIS_HOST)


@cli.command('pub:setupstream')
@click.argument('backend')
@click.argument('servers')
@click.pass_context
def pub_set_upstream(ctx, backend='ysgge___release___release', servers='127.0.0.1:8889'):
    """
    backend -- str
    servers -- str, comma split
    """
    servers = [s.strip() for s in servers.split(',')]
    ctx.obj['ELB'].set_upstream(backend, servers)


@cli.command('pub:delupstream')
@click.argument('backend')
@click.pass_context
def pub_del_upstream(ctx, backend='ysgge___release___release'):
    """
    backend -- str
    """
    ctx.obj['ELB'].delete_upstream(backend)


@cli.command('pub:setrule')
@click.argument('domain')
@click.argument('backend')
@click.pass_context
def pub_set_rule(ctx, domain='www.elb3test.org', backend='general'):
    RULE['rules']['rule0']['conditions'] = [{'backend': backend}]
    RULE['backends'] = [backend]
    RULE['default'] = backend
    ctx.obj['ELB'].set_rule(domain, RULE)


@cli.command('pub:delrule')
@click.argument('domains')
@click.pass_context
def pub_del_rule(ctx, domains='www.elb3test.org'):
    domains = [s.strip() for s in domains.split(',')]
    ctx.obj['ELB'].delete_rule(domains)


@cli.command('setcomplex')
@click.argument('domain')
@click.pass_context
def set_complext(ctx, domain):
    ctx.obj['ELB'].set_rule(domain, complex_rule)


if __name__ == '__main__':
    cli(obj={})
