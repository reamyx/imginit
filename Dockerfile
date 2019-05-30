#官方centos7镜像初始化,镜像TAG: imginit

FROM        centos
LABEL       function="imginit",maintainer="zhixia,reamyx@126.com"

#添加本地资源
ADD     imginit     /srv/imginit/

WORKDIR /srv/imginit

#基础工具和功能软件包
RUN     set -x \
        && yum -y install epel-release \
        && yum -y install man which libpcap ipset sqlite3 inotify-tools iproute \
                  psmisc sysvinit-tools nmap-ncat dropbear sshpass openvpn ppp unzip \
        && yum -y install gcc make automake openssh-server openssl-devel \
        && mkdir -p installtmp \
        && cd installtmp \
        \
        && curl https://codeload.github.com/reamyx/ppp-zxmodify/zip/master -o ppp-zxmodify.zip \
        && unzip ppp-zxmodify.zip \
        && cd ppp-zxmodify-master \
        && ./configure \
        && make \
        && make install \
        && cd - \
        && \cp -sf /usr/local/sbin/ppp* /usr/sbin/ \
        \
        && curl -L  https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 -o jq \
        && chmod +x ./jq \
        && mv -f ./jq /usr/local/bin \
        \
        && cd ../ \
        && \cp /usr/libexec/openssh/sftp-server /usr/libexec/sftp-server \
        && yum -y history undo last \
        && yum clean all \
        && rm -rf installtmp /tmp/* /etc/ppp/* \
        && find ../ -name "*.sh" -exec chmod +x {} \;

ENV       ZXDK_THIS_IMG_NAME    "imginit"

# ENTRYPOINT CMD
CMD [ "./initstart.sh" ]
