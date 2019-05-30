#!/bin/env sh
exit 0

#测试01
docker stop zt01; docker rm zt01; \
docker container run --detach --rm \
--name zt01 --hostname zt01 \
--network imvn --cap-add NET_ADMIN \
--sysctl "net.ipv4.ip_forward=1" \
--device /dev/ppp --device /dev/net/tun \
--volume /etc/localtime:/etc/localtime:ro \
--dns 192.168.15.192 --dns-search local \
registry.cn-hangzhou.aliyuncs.com/zhixia/imginit:base

docker network connect emvn zt01
docker container exec -it zt01 bash

#测试02,持久化
docker stop zt02; docker rm zt02; \
docker container run --detach --restart always \
--name zt02 --hostname zt02 \
--network imvn --cap-add NET_ADMIN \
--sysctl "net.ipv4.ip_forward=1" \
--device /dev/ppp --device /dev/net/tun \
--volume /etc/localtime:/etc/localtime:ro \
--dns 192.168.15.192 --dns-search local \
registry.cn-hangzhou.aliyuncs.com/zhixia/imginit:base

docker network connect emvn zt02
docker container exec -it zt02 bash
