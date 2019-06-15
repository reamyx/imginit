#官方centos7镜像初始化,镜像TAG: imginit

FROM        centos
LABEL       function="imginit",maintainer="zhixia,reamyx@126.com"

#添加本地资源
ADD     imginit     /srv/imginit/

WORKDIR /srv/imginit

#基础工具和功能软件包
RUN     set -x && cd \
        && yum -y install epel-release \
        && yum -y install man which nano libpcap ipset sqlite3 inotify-tools iproute \
                  psmisc sysvinit-tools nmap-ncat dropbear sshpass openvpn ppp unzip \
        && yum -y install gcc make automake openssh-server openssl-devel \
        \
        && curl https://codeload.github.com/reamyx/ppp-zxmd/zip/master -o ppp-zxmd.zip \
        && unzip ppp-zxmd.zip \
        && cd ppp-zxmd-master \
        && ./configure \
        && make \
        && make install \
        && cd - \
        && \cp -sf /usr/local/sbin/ppp* /usr/sbin/ \
        \
        && curl -L  https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 -o jq \
        && \cp /usr/libexec/openssh/sftp-server /usr/libexec/sftp-server \
        && ln -sf "./sleep" "$(dirname "$(which sleep)")/DoNothing" \
        && chmod +x jq /srv/imginit/srvctl \
        && mv -f jq /srv/imginit/srvctl /usr/local/bin \
        && yum -y history undo last \
        && yum clean all \
        && rm -rf /tmp/* /etc/ppp/* ~/*

ENV       ZXDK_THIS_IMG_NAME    "imginit"

# ENTRYPOINT CMD
CMD [ "./initstart.sh" ]
