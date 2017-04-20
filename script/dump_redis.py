#coding:utf8

import requests
import redis

NAME = 'internal'
UPSTREAM_KEY = '{}:upstream'.format(NAME)
RULES_KEY = '{}:rules'.format(NAME)

client = redis.Redis.from_url('127.0.0.1')

upstreams = requests.get('http://c2-docker-10.ricebook.link/__erulb__/upstream').json()
rules = requests.get('http://c2-docker-9.ricebook.link/__erulb__/rule').json()

for key in rules:
    client.set(key, rules[key])
    client.hset(RULES_KEY, key, key.split(':')[1])

for key in upstreams:
    data = upstreams[key]
    ips = [s['addr'] for s in data]
    servers = ['server {};'.format(ip) for ip in ips]
    value = '\n'.join(servers)
    print(UPSTREAM_KEY, key, value)
    client.hset(UPSTREAM_KEY, key, value)
