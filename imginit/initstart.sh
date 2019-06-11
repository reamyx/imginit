#!/bin/env sh
PATH="/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin"; cd "$(dirname "$0")"
exec 4>&1; ECHO(){ echo "${@}" >&4; }; exec 3<>"/dev/null"; exec 0<&3;exec 1>&3;exec 2>&3

#容器启动日志
echo "Container startup with image [ $ZXDK_THIS_IMG_NAME ] at \
[ $( date "+%F/%T/%Z" ) ], local name [ $HOSTNAME ]."

#辅助程序
ln -sf "./sleep" "$(dirname "$(which sleep)")/DoNothing"
[ -f "./srvctl" ] && { chmod +x "./srvctl"; ( setsid "./srvctl" "syslink" & ); }

#非首次启动时忽略来自环境变量的配置数据并使用历史目标服务名称
TSFL="./TargetSrv.Dir"
[ -r "$TSFL" ] && { SRVCFG=""; read -t 1 SRVNAME < "$TSFL"; SRVNAME="${SRVNAME##*/}"; }

#若存在指定服务名称命名的兄弟目录则切换其为目标服务目录
SRVNAME="${SRVNAME##*/*}"; SRVNAME="${SRVNAME:+../$SRVNAME}"
echo "$SRVNAME" > "$TSFL"; cd "$SRVNAME" || rm -rf "$TSFL"

#优先执行用户自定义初始化程序
[[ -f "./init.sh" && -x "./init.sh" ]] && {
    ECHO "Found and used customization init-progranm [ $PWD/init.sh ]."; exec "./init.sh"; }

#拨号程序,配置文件,重启计数文件...
POEDL="../imginit/inetdial.sh"
CFGFL="./workcfg.json"
CNTFL="./service.run.count"
OVDIR="../imginit/ovpn"
OVPWD="$OVDIR/pwd"

#若存在来自环境变量的配置数据则覆写到功能配置文件
touch "$CFGFL"; [ -n "$SRVCFG" ] && {
    FMTCFG="$( echo "$SRVCFG" | jq -sM ".[0]|objects" )"
    echo "${FMTCFG:-$SRVCFG}" > "$CFGFL"; unset FMTCFG; SRVCFG=""; }

#从功能配置文件读取配置数据
CFG_CHECK() {
    local CFG="$( jq -scM ".[0]|objects" "$CFGFL" )"
    [ -z "$CFG" ] && CFG="{ \"workwatch\": \"15\" }" && \
    ECHO "Configuration envionment variables or file invalid, Be ignored."
    [ "$1" == "intcfg" ] && INTCFG="$CFG" || SRVCFG="$CFG"; }

#管道消息接收和发送过程,消息空窗期间可用作延时阻塞
MSGPF="../imginit/EVENT.MSGPIPE.INIT"; MSGLN=(); MSGFD=""
MSG_DELAY() {
    [ -p "$MSGPF" ] || { rm -rf "$MSGPF"; mkfifo "$MSGPF"; }
    [[ "$1" =~ ^"CLOSE"|"CLEAN"$ ]] && { exec 98<&-; MSGFD=""
    [ "$1" == "CLEAN" ] && rm -rf "$MSGPF"; return; }
    [ -z "$MSGFD" ] && { exec 98<>"$MSGPF" && MSGFD=98; }
    [ -z "$MSGFD" ] && return; [ "$1" == "SEND"  ] && { 
    flock -x -w 5 98; echo "${@:2}" >&98; flock -u 98; return; }
    MSGLN=(); [ "$1" == "INIT" ] && return
    read -t "$1" -u 98 MSGLN[0]; MSGLN=( ${MSGLN[0]} ); }
MSG_DELAY INIT

#初始化延时
CFG_CHECK; DELAY="$( echo "$SRVCFG" | jq -r ".initdelay|numbers" )"
[ -z "$DELAY" ] && { DELAY=2; ECHO "Parameter [ initdelay ] invalid, Default value: [ 2 ]."; }
MSG_DELAY "$DELAY"

#防火墙初始化:基本规则
iptables -t filter -F
iptables -t filter -N SRVLCH
iptables -t filter -N INTLCH
iptables -t filter -N SRVFWD
iptables -t filter -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -t filter -A INPUT -j SRVLCH
iptables -t filter -A INPUT -j INTLCH
iptables -t filter -A INPUT -i lo -j ACCEPT
iptables -t filter -A INPUT -i tuninits -j ACCEPT
iptables -t filter -A INPUT -i tuninitc -j ACCEPT
iptables -t filter -A INPUT -j REJECT --reject-with icmp-host-prohibited
iptables -t filter -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -t filter -A FORWARD -j SRVFWD
iptables -t filter -A FORWARD -j REJECT --reject-with icmp-admin-prohibited

iptables -t nat -N SRVDNAT
iptables -t nat -N SRVSNAT
iptables -t nat -F SRVDNAT
iptables -t nat -F SRVSNAT
iptables -t nat -D PREROUTING  -j SRVDNAT
iptables -t nat -D POSTROUTING -j SRVSNAT
iptables -t nat -I PREROUTING  1 -j SRVDNAT
iptables -t nat -I POSTROUTING 1 -j SRVSNAT

iptables -t mangle -N SRVMFW
iptables -t mangle -N SRVMPE
iptables -t mangle -F SRVMFW
iptables -t mangle -F SRVMPE
iptables -t mangle -I FORWARD 1 -j SRVMFW
iptables -t mangle -I PREROUTING 1 -j SRVMPE

#防火墙: 应用业务规则
APPLY_FW_RULE() {
    [ "$1" == "keepalive" ] && return
    [ -z "$INTCFG" ] && CFG_CHECK "intcfg"
    iptables -t filter -F INTLCH
    iptables -t filter -A INTLCH -p tcp -m multiport --dport \
    "$( echo "$INTCFG" | jq -r ".firewall.tcpportpmt|strings" )" -m conntrack --ctstate NEW -j ACCEPT
    iptables -t filter -A INTLCH -p udp -m multiport --dport \
    "$( echo "$INTCFG" | jq -r ".firewall.udpportpmt|strings" )" -m conntrack --ctstate NEW -j ACCEPT
    [[ "$( echo "$INTCFG" | jq -r ".firewall.icmppermit|strings" )" =~ ^"YES"|"yes"$ ]] \
    && iptables -t filter -A INTLCH -p icmp -m limit --limit 100/sec --limit-burst 300 -j ACCEPT
    [[ "$( echo "$INTCFG" | jq -r ".firewall.igmppermit|strings" )" =~ ^"YES"|"yes"$ ]] \
    && iptables -t filter -A INTLCH -p igmp -j ACCEPT
    [[ "$( echo "$INTCFG" | jq -r ".firewall.grepermit|strings" )" =~ ^"YES"|"yes"$ ]] \
    && iptables -t filter -A INTLCH -p gre -j ACCEPT
    [[ "$( echo "$INTCFG" | jq -r ".firewall.esppermit|strings" )" =~ ^"YES"|"yes"$ ]] \
    && iptables -t filter -A INTLCH -p esp -j ACCEPT    
    [[ "$( echo "$INTCFG" | jq -r ".firewall.ahpermit|strings" )" =~ ^"YES"|"yes"$ ]] \
    && iptables -t filter -A INTLCH -p ah -j ACCEPT
    ECHO "Firewall configuration update completed."; }
    
#SSH服务初始化
SSHNM="DropBear-sshsrv"; SSHPM=""; pkill -f "$SSHNM"; SSHRL=(); SSHWCM="./ssh.welcome"
SSH_WELCOME() {
    echo -e "\nWelcome to use docker image \"imginit:multisrv\"." > "$SSHWCM"
    echo -e "Problem feedback to reamyx@126.com, thank you.\n" >> "$SSHWCM"; }
SSH_SRV_UP() {
    [ "$1" == "keepalive" ] && { [ -z "$SSHPM" ] || pidof "$SSHNM" && return; }
    [ -z "$INTCFG" ] && CFG_CHECK "intcfg"; iptables -t filter -D INTLCH "${SSHRL[@]}"
    [[ "$( echo "$INTCFG" | jq -r ".sshsrv.enable|strings" )" =~ ^"YES"|"yes"$ ]] \
    || { pkill -f "$SSHNM"; SSHPM=""; return; }
    #参数更新或服务失败时重启,执行前配置准入规则并配置Banner消息
    local SSHPORT="$( echo "$INTCFG" | jq -r ".sshsrv.sshport|numbers" )"
    local ROOTPWD="$( echo "$INTCFG" | jq -r ".sshsrv.rootpwd|strings" )"
    ROOTPWD="${ROOTPWD:-abc000}"; SSHPORT="${SSHPORT:-8022}"
    [ "$SSHPM" == "$SSHPORT-$ROOTPWD" ] && pidof "$SSHNM" && {
        iptables -t filter -A INTLCH "${SSHRL[@]}"; return; }
    pkill -f "$SSHNM"; SSHPM="$SSHPORT-$ROOTPWD"; SSH_WELCOME
    SSHRL=( -p tcp -m tcp --dport "$SSHPORT" -m conntrack --ctstate NEW
            -m limit --limit 4/min --limit-burst 20 -j ACCEPT )
    iptables -t filter -A INTLCH "${SSHRL[@]}"; echo "$ROOTPWD" | passwd --stdin root
    for ID in {1..10}; do MSG_DELAY 0.4; pidof "$SSHNM" || break; done
    ( MSG_DELAY CLOSE; exec -a "$SSHNM" dropbear \
      -F -E -R -a -b "$SSHWCM" -I 600 -K 30 -p "$SSHPORT" )&
    ECHO "SSH service [re]started with port [ $SSHPORT} ]."; }
    
#OVPN远程接入服务初始化
OVSNM="ovpn-ser-init"; OVSPM=""; pkill -f "$OVSNM"; OVSRL=()
OVPN_SRV_UP() {
    [ "$1" == "keepalive" ] && { [ -z "$OVSPM" ] || pidof "$OVSNM" && return; }
    [ -z "$INTCFG" ] && CFG_CHECK "intcfg"; iptables -t filter -D INTLCH "${OVSRL[@]}"
    [[ "$( echo "$INTCFG" | jq -r ".ovpnser.enable|strings" )" =~ ^"YES"|"yes"$ ]] \
    || { pkill -f "$OVSNM"; OVSPM=""; return; }
    #参数更新或服务失败时重启,执行前配置准入规则
    local SRVPORT="$( echo "$INTCFG" | jq -r ".ovpnser.srvport|numbers" )"
    local DEFUSER="$( echo "$INTCFG" | jq -r ".ovpnser.defuser|strings" )"
    local DEFPSWD="$( echo "$INTCFG" | jq -r ".ovpnser.defpswd|strings" )"
    SRVPORT="${SRVPORT:-1258}"
    [ -z "$DEFUSER" ] && { DEFUSER="ovinit"; DEFPSWD="ovinit123"; }
    [ "$OVSPM" == "$SRVPORT-$DEFUSER-$DEFPSWD" ] && pidof "$OVSNM" && {
        iptables -t filter -A INTLCH "${OVSRL[@]}"; return; }
    pkill -f "$OVSNM"; OVSPM="$SRVPORT-$DEFUSER-$DEFPSWD"
    OVSRL=( -p tcp -m tcp --dport "$SRVPORT" -m conntrack --ctstate NEW -j ACCEPT )
    iptables -t filter -A INTLCH "${OVSRL[@]}"; echo "$DEFPSWD" > "$OVPWD/$DEFUSER.pwd"
    for ID in {1..10}; do MSG_DELAY 0.4; pidof "$OVSNM" || break; done
    ( MSG_DELAY CLOSE; exec -a "$OVSNM" openvpn \
      --cd "$OVDIR" --lport "$SRVPORT" --config "ovser.conf" )&
    ECHO "Openvpn service [re]started with port [ $SRVPORT} ]."; }
    
#OVPN远程连接服务初始化
OVCNM="ovpn-clt-init"; OVCPM=""; pkill -f "$OVCNM"
OVPN_CLT_UP() {
    [ "$1" == "keepalive" ] && { [ -z "$OVCPM" ] || pidof "$OVCNM" && return; }
    [ -z "$INTCFG" ] && CFG_CHECK "intcfg"
    [[ "$( echo "$INTCFG" | jq -r ".ovpnclt.enable|strings" )" =~ ^"YES"|"yes"$ ]] \
    || { pkill -f "$OVCNM"; OVCPM=""; return; }
    #参数更新或服务失败时重启
    local RMTPORT="$( echo "$INTCFG" | jq -r ".ovpnclt.rmtport|numbers"  )"
    local RMTADDR="$( echo "$INTCFG" | jq -r ".ovpnclt.rmtaddr|strings"  )"
    local RMTUSER="$( echo "$INTCFG" | jq -r ".ovpnclt.username|strings" )"
    local RMTPSWD="$( echo "$INTCFG" | jq -r ".ovpnclt.password|strings" )"
    RMTPORT="${RMTPORT:-1258}"; [ -z "$RMTUSER" ] && { RMTUSER="ovinit"; RMTPSWD="ovinit123"; }
    [ "$OVCPM" == "$RMTPORT-$RMTADDR-$RMTUSER-$RMTPSWD" ] && pidof "$OVCNM" && return
    pkill -f "$OVCNM"; OVCPM="$RMTPORT-$RMTADDR-$RMTUSER-$RMTPSWD"
    echo -e "$RMTUSER\n$RMTPSWD" > "$OVPWD/default.up"
    for ID in {1..10}; do MSG_DELAY 0.4; pidof "$OVCNM" || break; done
    ( MSG_DELAY CLOSE; exec -a "$OVCNM" openvpn \
      --cd "$OVDIR" --remote "$RMTADDR" --rport "$RMTPORT" --config "ovclt.conf" )&
    ECHO "Openvpn client [re]started with target [ $RMTADDR:$RMTPORT} ]."; } 
    
#拨号网络初始化
INETPM=""; $POEDL "down"
INET_DIAL_UP() {
    [ "$1" == "keepalive" ] && { [ -z "$INETPM"  ] || $POEDL "pid" && return; }
    [ -z "$INTCFG" ] && CFG_CHECK "intcfg"
    [[ "$( echo "$INTCFG" | jq -r ".inetdail.enable|strings" )" =~ ^"YES"|"yes"$ ]] \
    || { $POEDL "down"& INETPM=""; return; }
    #配置参数有变化或者拨号进程失败时重启拨号
    local USER="$( echo "$INTCFG" | jq -r ".inetdail.dialuser|strings" )"
    local PSWD="$( echo "$INTCFG" | jq -r ".inetdail.dialpswd|strings" )"
    local INTF="$( echo "$INTCFG" | jq -r ".inetdail.dialintf|strings" )"
    local ENGW="$( echo "$INTCFG" | jq -r ".inetdail.usedefgw|strings" )"
    [[ "$ENGW" =~ ^"YES"|"yes"$ ]] && ENGW="DEFROUTE PATHBACK PEERDNS" || ENGW="PATHBACK"
    [ "$INETPM" == "$USER-$PSWD-$INTF-$ENGW" ] && $POEDL "pid" && return
    INETPM="$USER-$PSWD-$INTF-$ENGW"
    ( MSG_DELAY CLOSE; exec $POEDL "upfront" "$USER" "$PSWD" "$INTF" "$ENGW" )&
    ECHO "PPPOE dialing [re]started in interface [ ${INTF:-<Automatic Detection>} ]."; }

#支持服务启动过程
INIT_SRV_STARTUP() {
    #防火墙,ssh服务,远程接入,远程连接,拨号网络,保活启动时复位配置数据
    [ "$1" == "keepalive" ] && INTCFG="" || INTCFG="$SRVCFG"; APPLY_FW_RULE "$1"
    SSH_SRV_UP "$1"; OVPN_SRV_UP "$1"; OVPN_CLT_UP "$1"; INET_DIAL_UP "$1"; }

#清除容器内服务进程并等待指定时长后终止运行
TREM_AND_EXIT() {
    trap "" SIGQUIT SIGTERM; local PIDS=( $( exec ps --ppid 1 -o pid ) )
    for PT in "${PIDS[@]:1}"; do kill "$PT"; done
    for PT in {1..12}; do MSG_DELAY "0.5"; PIDS=( $( exec ps ax -o pid ) )
    (( "${#PIDS[@]}" <= "${EXCN:-3}" )) && break; done; MSG_DELAY CLOSE; exit 0; }

#终止信号处理
trap "TREM_AND_EXIT" SIGQUIT SIGTERM

#初始化运行控制,启动目标服务
for PT in ./EnvResume-*; do
    [[ -f "$PT" && -x "$PT" ]] && ( MSG_DELAY CLOSE; exec "$PT" ); done
RCNT=0; PT=""; EXCN=""; MSGLN=(); while true; do
    #测试和响应容器终止指令
    [ "${MSGLN[0]}" == "SRVSTOP" ] && { ECHO "Instruct Stoped."; EXCN="4"; break; }
    
    #(重)启动计数和日志
    (( ++RCNT >= 4294967296 )) && RCNT=1
    echo "RestartCount: $RCNT" > "$CNTFL"
    ECHO -e "\nService [re]start.. ( RestartCount: $RCNT )"
    
    #Reload配置数据,检测并重启支持服务
    CFG_CHECK; INIT_SRV_STARTUP
    
    START="$( echo "$SRVCFG" | jq -r ".workstart|strings" )"
    PERDC="$( echo "$SRVCFG" | jq -r ".workwatch|numbers" )"
    INTVL="$( echo "$SRVCFG" | jq -r ".workintvl|numbers" )"
    
    #空启动命令使用事件消息读取过程进行延时
    [ -z "$START" ] && { echo "Internal-Delay ..." >> "$CNTFL"; MSG_DELAY 600; continue; }
    
    #服务启动程序指定为"DoNothing"或不可用时使用"DoNothing 600",终止历史延时服务
    [ "$START" == "DoNothing" ] && START="DoNothing 600"; pkill "DoNothing"; CMD=( $START )
    [ -x "$( which "${CMD[0]}" )" ] || {
        ECHO "The service \"${CMD[0]}\" replaced by \"DoNothing 600\"."
        CMD=( "DoNothing" "600" ); }
    
    #非守护执行: 服务程序执行失败或终止时停止容器
    [ -z "$PERDC" ] && {
        echo "None-Daemoned" >> "$CNTFL"; MSG_DELAY CLOSE
        exec "${CMD[@]}"; ECHO "Exec failed, exit."; exit 126; }
    
    #重启延时参数
    (( INTVL < 5 )) && { INTVL=5; ECHO "Parameter \"workintvl\" invalid, Default: $INTVL."; }
    
    #守护执行: 服务程序进行终止后时延时重启
    (( PERDC == 0 )) && {
        echo "With-Daemoned( Delay: $INTVL )" >> "$CNTFL"
        ( MSG_DELAY CLOSE; exec "${CMD[@]}" ); MSG_DELAY "$INTVL"; continue; }
    
    #状态测试执行: 服务启动后周期性测试目标和支持服务状态并在其失败时执行重启
    echo "Status-Monitored( Delay: $INTVL )" >> "$CNTFL"
    ( MSG_DELAY CLOSE; setsid "${CMD[@]}" & ); MSG_DELAY "$INTVL"
    
    #周期性任务启动,目标任务需要自行处理重入及与其它任务的资源争用
    (( PERDC < 10 )) && PERDC=10; export SMCNT="1"; export PERDC
    while true; do
        #测试和响应服务控制指令
        [[ "${MSGLN[0]}" == "SRVRESTART" || "${MSGLN[0]}" == "SRVSTOP" ]] && break
        
        #更新服务测试情况
        PT="Delay: $INTVL, Periodic: $PERDC, MCount: $SMCNT"
        echo -e "RestartCount: $RCNT\nStatus-Monitored( $PT )" > "$CNTFL"
        
        #例行任务,"PeriodicRT-"前缀,每周期无条件执行
        for PT in ./PeriodicRT-*; do [[ -f "$PT" && -x "$PT" ]] && \
        ( MSG_DELAY CLOSE; setsid "$PT" & ); done
        
        #同步状态测试,"PeriodicST-"前缀,失败状态将导致目标服务重启
        for PT in ./PeriodicST-*; do [[ -f "$PT" && -x "$PT" ]] && \
        { ( MSG_DELAY CLOSE; exec "$PT" ) || break 2; }; done
        
        #维护任务,"PeriodicMT-"前缀,仅在目标服务运行正常时执行
        for PT in ./PeriodicMT-*; do [[ -f "$PT" && -x "$PT" ]] && \
        ( MSG_DELAY CLOSE; setsid "$PT" & ); done
        
        #支持服务保活仅从失败状态恢复时reload配置数据,周期延时
        INIT_SRV_STARTUP "keepalive"; MSG_DELAY "$PERDC"
        
        #状态测试计数器更新,可用于周期扩展
        (( ++SMCNT >= 4294967296 )) && SMCNT=1; done
    export -n SMCNT; export -n PERDC; done

#终止容器,建议使用容器管理执行终止操作
MSG_DELAY CLEAN; TREM_AND_EXIT

exit 0
