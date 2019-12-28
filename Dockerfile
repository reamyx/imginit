#官方centos7镜像初始化,镜像TAG: imginit

FROM        centos:7
LABEL       function="imginit",maintainer="zhixia,reamyx@126.com"

#添加本地资源
ADD     imginit     /srv/imginit/

WORKDIR /srv/imginit

#基础工具和功能软件包
RUN     set -x && cd && rm -rf * \
        && yum clean all \
        && rm -rf /etc/yum.repos.d/* \
        && curl -o /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo \
        && sed -i "/mirrors.cloud.aliyuncs.com/d" /etc/yum.repos.d/CentOS-Base.repo \
        && sed -i "/mirrors.aliyuncs.com/d" /etc/yum.repos.d/CentOS-Base.repo \
        && curl -o /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7 https://mirrors.aliyun.com/centos/RPM-GPG-KEY-CentOS-7 \
        && rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7 \
        && curl -o /etc/yum.repos.d/epel.repo http://mirrors.aliyun.com/repo/epel-7.repo \
        && curl -o /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7 https://mirrors.aliyun.com/epel/RPM-GPG-KEY-EPEL-7 \
        && rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7 \
        \
        && yum -y install man which nano unzip libpcap ipset inotify-tools psmisc sysvinit-tools \
                  iproute nmap-ncat sqlite dropbear sshpass ppp keepalived git \
        && yum -y install gcc make automake openssh-server openssl-devel \
        \
        && git clone https://github.com/reamyx/ppp-zxmd \
        && cd ppp-zxmd \
        && ./configure \
        && make \
        && make install \
        && \cp -sf /usr/local/sbin/ppp* /usr/sbin/ \
        && rm -rf /etc/ppp/* \
        && cd \
        \
        && curl -L -o jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 \
        && chmod +x jq \
        && mv -f jq /usr/local/bin \
        \
        && \cp /usr/libexec/openssh/sftp-server /usr/libexec/sftp-server \
        && ln -sf "./sleep" "$(dirname "$(which sleep)")/DoNothing" \
        \
        && chmod +x /srv/imginit/srvctl \
        && mv -f /srv/imginit/srvctl /usr/local/bin \
        \
        && yum -y history undo last \
        && yum clean all \
        && rm -rf /tmp/* ./*

ENV       ZXDK_THIS_IMG_NAME    "imginit"

# ENTRYPOINT CMD
CMD [ "./initstart.sh" ]
