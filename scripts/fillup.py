import json
import redis


r = redis.Redis()
r.delete('ELB:filter')


# fillup domains
domains = {
    'a.muroq.com': 'app1:pod1:entry1',
    'b.muroq.com': 'app2:pod2:entry2',
}
r.set('ELB:domainmap', json.dumps(domains))

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
