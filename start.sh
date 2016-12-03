#!/bin/sh

ERU_INFO=elb3:${ERU_NODE_IP}
nginx -p /erulb3/server -c /erulb3/conf/release.conf
