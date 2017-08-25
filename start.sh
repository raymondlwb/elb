#!/bin/sh

ERU_INFO=elb:${ERU_NODE_IP} nginx -p /home/erulb/server -c /home/erulb/conf/release.conf
