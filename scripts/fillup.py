import json
import redis


r = redis.Redis()
r.delete('ELB:filter')
r.delete('ELB:data')


# fillup domains
domains = {
    'a.muroq.com': 'app1_pod1_entry1',
    'a.muroq.com/4/': 'app1_pod1_entry1_xxx',
    'b.muroq.com': 'app2_pod2_entry2',
}
upstream = {
    'app1_pod1_entry1': 'server 10.100.0.18:5000;',
    'app2_pod2_entry2': 'server 10.10.1.1:5000; server 10.10.1.2:5000;',
    'app1_pod1_entry1_xxx': 'server 10.6.9.203:8180;',
}

for domain, key in domains.iteritems():
    r.hset('ELB:domainmap', domain, key)
for key, up in upstream.iteritems():
    r.hset('ELB:upstream', key, up)

# fillup limits
reqlimits = {
    'a.muroq.com/a': 5,
    'a.muroq.com/b': 500,
    'b.muroq.com/x': 1000,
    'b.muroq.com/y': 500,
}
r.hset('ELB:filter', 'limit', json.dumps(reqlimits))

# fillup ua
ua = ['chrome', 'safari']
r.hset('ELB:filter', 'ua', json.dumps(ua))

# fillup referrer
refs = ['a.muroq.com', 'c.muroq.com']
r.hset('ELB:filter', 'referrer', json.dumps(refs))
