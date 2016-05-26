from gevent.monkey import patch_all
patch_all()
import sys
import gevent
import requests


def request_url(url, count):
    for _ in range(count):
        r = requests.get(url)
        print r.status_code
        gevent.sleep(0.1)


def run(url, count):
    greenlets = [gevent.spawn(request_url, url, count) for _ in range(10)]
    gevent.joinall(greenlets)
    print 'done'


if __name__ == '__main__':
    url = sys.argv[-2]
    count = int(sys.argv[-1])
    run(url, count)
