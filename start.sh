#!/bin/sh

ERU_INFO=elb3:${ERU_NODE_IP} nginx -p /home/erulb3/server -c /home/erulb3/conf/release.conf
