#!/bin/bash
cd `dirname $0`
WORKDIR=$(cd $(dirname $0); pwd)
pid_file=$WORKDIR/pid/pid_mtproxy

check_sys(){
    local checkType=$1
    local value=$2

    local release=''
    local systemPackage=''

    if [[ -f /etc/redhat-release ]]; then
        release="centos"
        systemPackage="yum"
    elif grep -Eqi "debian|raspbian" /etc/issue; then
        release="debian"
        systemPackage="apt"
    elif grep -Eqi "ubuntu" /etc/issue; then
        release="ubuntu"
        systemPackage="apt"
    elif grep -Eqi "centos|red hat|redhat" /etc/issue; then
        release="centos"
        systemPackage="yum"
    elif grep -Eqi "debian|raspbian" /proc/version; then
        release="debian"
        systemPackage="apt"
    elif grep -Eqi "ubuntu" /proc/version; then
        release="ubuntu"
        systemPackage="apt"
    elif grep -Eqi "centos|red hat|redhat" /proc/version; then
        release="centos"
        systemPackage="yum"
    fi

    if [[ "${checkType}" == "sysRelease" ]]; then
        if [ "${value}" == "${release}" ]; then
            return 0
        else
            return 1
        fi
    elif [[ "${checkType}" == "packageManager" ]]; then
        if [ "${value}" == "${systemPackage}" ]; then
            return 0
        else
            return 1
        fi
    fi
}

function pid_exists(){
  local exists=`ps aux | awk '{print $2}'| grep -w $1`
  if [[ ! $exists ]]
  then
    return 0;
  else
    return 1;
  fi
}

install(){
  cd $WORKDIR
  if [ ! -d "./pid" ];then
    mkdir "./pid"
  fi

  if check_sys packageManager yum; then
    yum install -y openssl-devel zlib-devel
    yum groupinstall -y "Development Tools"
  elif check_sys packageManager apt; then
    apt-get -y update
    apt install -y git curl build-essential libssl-dev zlib1g-dev
  fi

  if [ ! -d 'MTProxy' ];then
    git clone https://github.com/TelegramMessenger/MTProxy
  fi;
  cd MTProxy
  make && cd objs/bin
  cp -f $WORKDIR/MTProxy/objs/bin/mtproto-proxy $WORKDIR
  cd $WORKDIR
}

function rand(){  
  min=$1
  max=$(($2-$min+1))
  num=$(date +%s%N)
  echo $(($num%$max+$min))
}  
input_port=$(rand 2000 30000)
input_manage_port=$(rand 30001 65500)
input_domain="azure.microsoft.com"

curl -s https://core.telegram.org/getProxySecret -o proxy-secret
curl -s https://core.telegram.org/getProxyConfig -o proxy-multi.conf
secret=$(head -c 16 /dev/urandom | xxd -ps)
cat >./mtp_config <<EOF
secret="${secret}"
port=${input_port}
web_port=${input_manage_port}
domain="${input_domain}"
EOF
  echo -e "配置已经生成完毕!"
}

status_mtp(){
  if [ -f $pid_file ];then
    pid_exists `cat $pid_file`
    if [[ $? == 1 ]];then
      return 1
    fi
  fi
  return 0
}

info_mtp(){
  status_mtp
  if [ $? == 1 ];then
    source ./mtp_config
    public_ip=$(curl -s https://api.ip.sb/ip --ipv4)
    domain_hex=$(xxd -pu <<< $domain | sed 's/0a//g')
    client_secret="ee${secret}${domain_hex}"
    echo -e "TMProxy+TLS代理: \033[32m运行中\033[0m"
    echo -e "服务器IP：\033[31m$public_ip\033[0m"
    echo -e "服务器端口：\033[31m$port\033[0m"
    echo -e "MTProxy Secret:  \033[31m$secret\033[0m"
    echo -e "TG一键链接: https://t.me/proxy?server=${public_ip}&port=${port}&secret=${client_secret}"
    echo -e "TG一键链接: tg://proxy?server=${public_ip}&port=${port}&secret=${client_secret}"
  else
    echo -e "TMProxy+TLS代理: \033[33m已停止\033[0m"
  fi
}


run_mtp(){
  cd $WORKDIR
  status_mtp
  if [ $? == 1 ];then
    echo -e "提醒：\033[33mMTProxy已经运行，请勿重复运行!\033[0m"
  else
    source ./mtp_config
    nat_ip=$(echo $(ip a | grep inet | grep -v 127.0.0.1 | grep -v inet6 | awk '{print $2}' | cut -d "/" -f1 |awk 'NR==1 {print $1}'))
    public_ip=`curl -s https://api.ip.sb/ip --ipv4`
    nat_info=""
    if [[ $nat_ip != $public_ip ]];then
      nat_info="--nat-info ${nat_ip}:${public_ip}"
    fi
    ./mtproto-proxy -u nobody -p $web_port -H $port -S $secret --aes-pwd proxy-secret proxy-multi.conf -M 1 --domain $domain $nat_info >/dev/null 2>&1 &
    
    echo $!>$pid_file
    sleep 2
    info_mtp
  fi
}

debug_mtp(){
  cd $WORKDIR
  source ./mtp_config
  nat_ip=$(echo $(ip a | grep inet | grep -v 127.0.0.1 | grep -v inet6 | awk '{print $2}' | cut -d "/" -f1 |awk 'NR==1 {print $1}'))
  public_ip=`curl -s https://api.ip.sb/ip --ipv4`
  nat_info=""
  if [[ $nat_ip != $public_ip ]];then
      nat_info="--nat-info ${nat_ip}:${public_ip}"
    fi
  echo "当前正在运行调试模式："
  echo -e "\t你随时可以通过 Ctrl+C 进行取消操作"
  echo " ./mtproto-proxy -u nobody -p $web_port -H $port -S $secret --aes-pwd proxy-secret proxy-multi.conf -M 1 --domain $domain $nat_info"
  ./mtproto-proxy -u nobody -p $web_port -H $port -S $secret --aes-pwd proxy-secret proxy-multi.conf -M 1 --domain $domain $nat_info
}

stop_mtp(){
  local pid=`cat $pid_file`
  kill -9 $pid
  pid_exists $pid
  if [[ $pid == 1 ]]
  then
    echo "停止任务失败"
  fi
}


param=$1
if [[ "start" == $param ]];then
  echo "即将：启动脚本";
  run_mtp
elif  [[ "stop" == $param ]];then
  echo "即将：停止脚本";
  stop_mtp;
elif  [[ "debug" == $param ]];then
  echo "即将：调试运行";
  debug_mtp;
elif  [[ "restart" == $param ]];then
  stop_mtp
  run_mtp
else
  if [ ! -f "$WORKDIR/mtp_config" ];then
    echo "MTProxyTLS一键安装运行绿色脚本"
    echo "================================="
    install
    config_mtp
    run_mtp
  else
    echo "MTProxyTLS一键安装运行绿色脚本"
    echo "================================="
    info_mtp
    echo "================================="
    echo -e "配置文件: $WORKDIR/mtp_config"
    echo -e "卸载方式：直接删除当前目录下文件即可"
    echo "使用方式:"
    echo -e "\t启动服务 bash $0 start"
    echo -e "\t调试运行 bash $0 debug"
    echo -e "\t停止服务 bash $0 stop"
    echo -e "\t重启服务 bash $0 restart"
  fi
fi
