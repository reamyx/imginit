#!/bin/env sh
PATH="/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin"; cd "$(dirname "$0")"
exec 4>&1; ECHO(){ echo "${@}" >&4; }; exec 3<>"/dev/null"; exec 0<&3;exec 1>&3;exec 2>&3


#作为IPCP脚本调用,准入条件为存在IPCP脚本特定的环境变量
[[ -n "$IFNAME" && -n "$PPPLOGNAME" && -n "$PPPD_PID" ]] && {
    #事件类型及DDNS注册参数分离,LKEVT="PPPUP","PPPDW"分别指示连接启动和终止
    LKEVT="${CONNECT_TIME:+PPPDW}"; LKEVT="${LKEVT:-PPPUP}"; IPPM=" $6 "
    
    MAPURL="$( echo "$IPPM" | grep -Eo "MURL<[^[:space:]]*>MURL" )"
    MAPURL="${MAPURL:5}"; MAPURL="${MAPURL::-5}"
    
    RQPMUP="$( echo "$IPPM" | grep -Eo "PMUP<[^[:space:]]*>PMUP" )"
    RQPMUP="${RQPMUP:5}"; RQPMUP="${RQPMUP::-5}"
    
    RQPMDW="$( echo "$IPPM" | grep -Eo "PMDW<[^[:space:]]*>PMDW" )"
    RQPMDW="${RQPMDW:5}"; RQPMDW="${RQPMDW::-5}"
    
    NTFLPT="$( echo "$IPPM" | grep -Eo "NTFL<[^[:space:]]*>NTFL" )"
    NTFLPT="${NTFLPT:5}"; NTFLPT="${NTFLPT::-5}"
    
    INSTID="$( echo "$IPPM" | grep -Eo "INST<[^[:space:]]*>INST" )"
    INSTID="${INSTID:5}"; INSTID="${INSTID::-5}"
    
    #URL请求参数标记代换: <:ADDR:>地址代换 <:HOST:>主机名称代换
    RQPMUP="$( echo "$RQPMUP" | sed "s%<:HOST:>%$(hostname)%g;s%<:ADDR:>%$IPLOCAL%g" )"
    RQPMDW="$( echo "$RQPMDW" | sed "s%<:HOST:>%$(hostname)%g;s%<:ADDR:>%$IPLOCAL%g" )"
    
    #连接启动,测试指示标记条件配置默认路由,DNS及由来路径出口
    [ "$LKEVT" == "PPPUP" ] && {
        [ -z "${IPPM##* DEFROUTE *}" ] && {
            ip route add 0.0.0.0/1   dev "$IFNAME" metric 10 
            ip route add 128.0.0.0/1 dev "$IFNAME" metric 10; }
            
        [ -z "${IPPM##* PATHBACK *}" ] && {
            ip rule del lookup 17 pref 17
            ip rule add from "$IPLOCAL" lookup 17 pref 17
            ip route add default dev "$IFNAME" metric 10 table 17; }
            
        [[ -z "${IPPM##* PEERDNS *}" && -n "$DNS1$DNS2" ]] && sed -i \
        -e "/# Following 2 lines are created by \\\"inetdial\\\", Do not edit./d" \
        -e "/nameserver   \($DNS1\|$DNS2\)  /d" \
        -e "1i\\# Following 2 lines are created by \"inetdial\", Do not edit." \
        -e "1i\\nameserver   $DNS1  \nnameserver   $DNS2  " /etc/resolv.conf
        
        [[ -n "$MAPURL" && -n "$RQPMUP" ]] && \
        curl --connect-timeout 4 -X "POST" -d "$RQPMUP" "$MAPURL" &
        
        [[ -f "$NTFLPT" && -x "$NTFLPT" ]] && ( export INSTID; setsid "$NTFLPT" "UP" & ); }
        
    #连接终止,测试指示标记条件撤消默认路由,DNS及由来路径出口
    [ "$LKEVT" == "PPPDW" ] && {
        [ -z "${IPPM##* DEFROUTE *}" ] && {
            ip route del 0.0.0.0/1   dev "$IFNAME" metric 10 
            ip route del 128.0.0.0/1 dev "$IFNAME" metric 10; }
            
        [ -z "${IPPM##* PATHBACK *}" ] && {
            ip rule del lookup 17 pref 17
            ip route del default dev "$IFNAME" metric 10 table 17; }
            
        [[ -z "${IPPM##* PEERDNS *}" && -n "$DNS1$DNS2" ]] && sed -i \
        -e "/# Following 2 lines are created by \\\"inetdial\\\", Do not edit./d" \
        -e "/nameserver   \($DNS1\|$DNS2\)  /d" /etc/resolv.conf
        
        [[ -n "$MAPURL" && -n "$RQPMDW" ]] && \
        curl --connect-timeout 4 -X "POST" -d "$RQPMDW" "$MAPURL" &
        
        [[ -f "$NTFLPT" && -x "$NTFLPT" ]] && ( export INSTID; setsid "$NTFLPT" "DOWN" & ); }
        
    exit 0; }

#########################   以下为拨号程序逻辑   #########################

#名称项定义
INETIF="inet0"
RUNNM="$INETIF-pppd"
STATFL="inetdial.stat"

#启动参数初始化
PMINIT() {
    #从命令行和文件提取PPPOE基本参数
    USERNM=""; PASSWD=""; DIALIF=""; IPCPOP=""
    for SRC in "CMDL" "FILE"; do
        [ "$SRC" == "CMDL" ] && PMS=( "${@}" )
        [ "$SRC" == "FILE" ] && {
            PMS="./inetdial.cfg"; [ -r "$PMS" ] || continue
            read -t 1 PMS <"$PMS"; PMS=( $PMS ); }
        for((ID=0;ID<"${#PMS[@]}";ID++)); do \
        [[ "${PMS[ID]}" =~ ^-+$ ]] && PMS[ID]=""; done
        USERNM="${USERNM:-${PMS[0]}}"; PASSWD="${PASSWD:-${PMS[1]}}"
        DIALIF="${DIALIF:-${PMS[2]}}"; IPCPOP="${IPCPOP:-${PMS[*]:3}}"; done
    
    #名称注册路径和请求参数串,两者皆非空以使能名称注册
    # <:ADDR:>地址代换 <:HOST:>主机名称代换
    #环境变量"$NMV2"特定值指示启用namemapv2名称映射
    MAPURL=""
    [[ -z "$MAPURL" && "$NMV2" = "yes" ]] && \
    MAPURL="http://brxa.600vps.com:1253/namemapv2"
    RQPMUP="SIMPLEPM;<:HOST:>;V4HOST;<:ADDR:>"
    RQPMDW="SIMPLEPM;<:HOST:>;REMOVE"
    
    #定义扩展IPCP脚本,在默认IPCP脚本结束后异步执行
    TSFL="./TargetSrv.Dir"; NTFLPT=""
    [ -r "$TSFL" ] && read -t 1 NTFLPT < "$TSFL"
    NTFLPT="${NTFLPT:+$NTFLPT/}./DialNotify.sh"
    
    #生成实例ID
    read -t 1 INST < "/proc/sys/kernel/random/uuid"
    INST="$( echo "${INST:-$(uuidgen)}" | tr "[[:lower:]-]" "[[:upper:]\0]" )"
    INST="${INST::16}"
    
    #构造IPPARM参数及其它功能变量
    IPCPOP="${IPCPOP:-DEFROUTE PEERDNS PATHBACK}"
    IPCPOP="$IPCPOP MURL<$MAPURL>MURL PMUP<$RQPMUP>PMUP PMDW<$RQPMDW>PMDW"
    IPCPOP="$IPCPOP NTFL<$NTFLPT>NTFL INST<$INST>INST"
    PMS=(); MYNM="${0##*/}"; }

#拨号接口探测
BCIFS=()
IFDETECT() {
    BCIFS=(); local IFX=""; local RZT=()
    local IFBC=( $( ip link | awk '$3~/^<.*BROADCAST.*>$/{sub("[:@].*$","",$2);print $2}' ) )
    for IFX in "${IFBC[@]}"; do
        RZT=( $( pppoe-discovery -t 1 -a 2 -U -I "$IFX" ) ); [ "${#RZT[@]}" -lt 5 ] && continue
        BCIFS=( "${BCIFS[@]}" "$IFX ${RZT[3]} ${RZT[1]}" ); done; }

#拨号接口配置测试
IFCHECK() {
    [ -n "$DIALIF" ] && return; IFDETECT; local IFX=( ${BCIFS[0]} ); DIALIF="${IFX[0]}"
    [ -z "$DIALIF" ] && { echo "Dial Interface undefined and has't Detected."; exit 1; }; }

#拨号过程,确认历史实例结束后切换拨号
PPPOEDIAL() {
    echo "PRESTART: $INST" > "$STATFL"
    pkill -f "$RUNNM"; for ID in {1..20}; do sleep 0.5; pidof "$RUNNM" || break
        [ "$ID" == "20" ] && { echo "Instance($INST) Startup Failure." >> "$STATFL"; exit 2; } ; done
    echo "RUNNING: $INST" > "$STATFL"
    date "+%F/%T/%Z: PPPOE Dial Started.." >> "$STATFL"
    exec -a "$RUNNM" pppd ${FRONT:+nodetach} \
    lock persist holdoff 5 maxfail 0 lcp-echo-failure 6 lcp-echo-interval 5 \
    noauth refuse-eap nomppe user "$USERNM" password "$PASSWD" \
    ifname "$INETIF" ip-up-script "$PWD/$MYNM" ip-down-script "$PWD/$MYNM" usepeerdns \
    logfile "$STATFL" mtu 1492 mru 1492 ipparam "$IPCPOP" plugin rp-pppoe.so "$DIALIF" ; }

#拨号管理操作 up upfront watch down pid ifname ifaddr ipchk ifdetect
case "$1" in
    "up")
        PMINIT "${@:2}"; IFCHECK; FRONT="" PPPOEDIAL;;
    "upfront")
        PMINIT "${@:2}"; IFCHECK; FRONT="Y" PPPOEDIAL;;
    "watch")
        PMINIT "${@:2}"; IFCHECK
        ( while true; do ( FRONT="Y" PPPOEDIAL ); read -t 1 MSG < "$STATFL"
          [ "$MSG" != "RUNNING: $INST" ] && break; sleep 3; done; )& ;;
    "down")
        [ -w "$STATFL" ] && sed -i \
        "1i\\STOPED: By Indicate, $(date +%F/%T/%Z).\nHistory log:" "$STATFL"
        pkill -f "$RUNNM";;
    "pid")
        pidof "$RUNNM" >&4;;
    "ifname")
        ECHO "$INETIF"; ip -o addr show "$INETIF";;
    "ifaddr")
        ADDR="$( ip -o addr show "$INETIF" )"
        [ -n "$ADDR" ] && echo "$ADDR" | awk '{sub("/.*$","",$4); print $4}' >&4;;
    "ipchk")
        INFO="$( curl --connect-timeout 5 "https://api.ip.la/cn?json" )"
        which "jq" && INFO="$( echo "$INFO" | jq -M "." )"; ECHO "${INFO:-Check Failed.}";;
    "ifdetect")
        IFDETECT; for ID in "${BCIFS[@]}"; do ECHO "$ID"; done;;
    *)
        ECHO "Usage:"
        ECHO "  $0 < up | watch > [ username [ password [ interface [ FLAGS.. ]]]]"
        ECHO "  $0 < down | pid | ifname | ifaddr | ipchk | ifdetect >"
        ECHO
        ECHO "  FLAG: DEFROUTE  Apply default routing after connection is successful."
        ECHO "  FLAG: PEERDNS   Using the DNS provided by peer of the connection."
        ECHO "  FLAG: PATHBACK  Respond packets used interface which initializes incoming."
        ECHO "  NOTE: If no flags are specified, all flags are applied as default."
        ECHO "";; esac
exit

#环境变量
#  MACREMOTE=AC:4E:91:41:AD:98  [ PPPOE插件拨号时 ]
#  IFNAME=ppp120
#  CONNECT_TIME=23              [ 仅接口DOWN时可用 ]
#  IPLOCAL=192.168.16.20
#  PPPLOGNAME=root
#  BYTES_RCVD=43416             [ 仅接口DOWN时可用 ]
#  ORIG_UID=0
#  SPEED=115200
#  BYTES_SENT=73536             [ 仅接口DOWN时可用 ]
#  IPREMOTE=192.168.16.40
#  PPPD_PID=21420
#  PWD=/
#  PEERNAME=zxkt
#  DEVICE=/dev/pts/1
