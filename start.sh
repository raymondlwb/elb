#!/bin/sh

ERU_INFO=${ERU_NODE_IP}
nginx -p /erulb3/server -c /erulb3/conf/release.conf
