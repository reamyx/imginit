#!/bin/env sh
exit 0

#测试01
docker stop zt01; docker rm zt01; \
docker container run --detach --restart always \
--name zt01 --hostname zt01 \
--network imvn --cap-add NET_ADMIN \
--sysctl "net.ipv4.ip_forward=1" \
--device /dev/ppp --device /dev/net/tun \
--volume /etc/localtime:/etc/localtime:ro \
--dns 192.168.15.192 --dns-search local imginit

docker network connect emvn zt01
docker container exec -it zt01 bash

#测试02,持久化
SRVCFG='{"initdelay":3,
"workstart":"DoNothing",
"workwatch":15,"workintvl":10,
"firewall":{"tcpportpmt":"8000:8009",
"udpportpmt": "8000:8009"},
"sshsrv":{"enable":"yes",
"sshport": 8022,"rootpwd":"abc000"},
"inetdail":{"enable":"yes",
"dialuser":"a15368400819",
"dialpswd":"a123456"}}'; \
docker stop zt02; docker rm zt02; \
docker container run --detach --restart always \
--name zt02 --hostname zt02 \
--network imvn --cap-add NET_ADMIN \
--sysctl "net.ipv4.ip_forward=1" \
--device /dev/ppp --device /dev/net/tun \
--volume /etc/localtime:/etc/localtime:ro \
--dns 192.168.15.192 --dns-search local \
--env "SRVCFG=$SRVCFG" imginit; \
docker network connect emvn zt02

docker container exec -it zt02 bash
