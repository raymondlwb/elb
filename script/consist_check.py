#!/usr/bin/env python
# -*- coding: utf-8 -*-

import os
import click
import json
import requests
from redis import Redis

REDIS_HOST = os.getenv('REDIS_HOST', '127.0.0.1:6379')
ELB_URL = 'http://127.0.0.1'
ELB_NAME = 'ELB'
UPSTREAM_API = ELB_URL + '/__erulb__/upstream'
RULE_API =    ELB_URL + '/__erulb__/rule'
DEV_API =    ELB_URL + '/__erulb__/develop'
UPSTREAM_KEY = ELB_NAME + ':upstream'

RULE = {
    "rules_name": ["rule1"],
    "rules": {
        "rule0": {
            "type": "general",
            "conditions": [{"backend": "ysgge___release___release"}]
        }
    },
    "backends": ["ysgge___release___release"],
    "init_rule": "rule0",
    "default": "rule0"
}


@click.group()
@click.pass_context
def cli(ctx):
    ctx.obj['REDIS'] = Redis.from_url(REDIS_HOST)

@cli.command('check:upstream')
@click.pass_context
def check_upstream(ctx):
    api_res = requests.get(UPSTREAM_API).json()
    for backend in api_res:
        if backend == '_dyups_upstream_down_host_':
            continue
        api_servers = set([x['addr'] for x in api_res[backend]])
        redis_res = ctx.obj['REDIS'].hget(UPSTREAM_KEY, backend)
        if redis_res:
            redis_servers = set([x.strip(';') for x in redis_res.replace('server ', '').split('\n')])
        else:
            print backend
        if api_servers != redis_servers:
            click.echo('{}: not consist!'.format(backend))
            click.echo('api_servers: {}'.format(api_servers))
            click.echo('redis_servers: {}'.format(redis_servers))
            health = False
            return

    click.echo('all backend consist.')

@cli.command('check:rule')
@click.pass_context
def check_rule(ctx):
    api_res = requests.get(RULE_API).json()
    for domain_key in api_res:
        redis_res = ctx.obj['REDIS'].get(domain_key)
        if api_res[domain_key] != redis_res:
            health = False
            click.echo('{} not consist api: {}, redis: {}'.format(
                domain_key, api_res[domain_key], redis_res
            ))
            return

    click.echo('all rules consists.')


@cli.command('reload:upstream')
def reload_upstream():
    res = requests.put(UPSTREAM_API)
    click.echo(res.json())

@cli.command('reload:rule')
def reload_rule():
    res = requests.put(RULE_API)
    click.echo(res.json())

@cli.command('dev:upstream')
@click.argument('backend')
@click.argument('servers')
def dev_upstream(backend, servers):
    servers = ['server {};'.format(s.strip()) for s in servers.split(',')]
    data = {
        'func': 'UPSTREAM',
        'servers': servers,
        'key': backend,
    }
    res = requests.put(DEV_API, data=json.dumps(data))
    click.echo(res.json())

@cli.command('dev:rule')
@click.argument('domain')
def dev_rule(domain):
    key = ELB_NAME + ':' + domain
    data = {
        'func': 'RULE',
        'key': key,
        'rule': RULE,
    }
    res = requests.put(DEV_API, data=json.dumps(data))
    click.echo(res.json())


if __name__ == '__main__':
    cli(obj={})
