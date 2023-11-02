#!/bin/sh

###
# 参数一：请求类型 m1(泛解析, 90days), m2(单域名, 90days), m3(单域名, 170days)
# 参数二：域名
# 参数三：DNS类型 dns_ali / dns_cf 等等
# 参数四：CA类型 letsencrypt / zerossl / buypass
# 参数五：非空则为新注，需要注册CA
#
# 最新代码位于：https://jihulab.com/jetsung/docker-compose/-/tree/main/acme
##

###
# https://github.com/acmesh-official/acme.sh/wiki/Run-acme.sh-in-docker
###

PARAM1="${1}"

if [ "${PARAM1}" = "-h" ]; then
        printf "domain.sh m1 domain.com dns_ali zerossl new  
"
        exit 1
fi

if [ $# -lt 2 ]; then
        printf "params must be more than 3.
"
        exit 1
fi

set -e

ACTION="${PARAM1}"

DOMAIN="${2}"

#COMMAND=acme.sh

COMMAND="docker exec acme.sh"

DNS_TYPE="dns_ali"

CA_TYPE=""

if [ -z "${EMAIL}" ]; then
        EMAIL="jetsung@outlook.com"
fi

if [ -z "${DOMAIN}" ]; then 
        printf "\e[1;31mPlease input domain\e[0m\n"; exit 1;
fi

if [ -n "${3}" ]; then
        DNS_TYPE="${3}"
fi

if [ "no" = "${DNS_TYPE}" ]; then
        DNS_TYPE="dns_ali"
fi

if [ -n "${4}" ]; then
        CA_TYPE="${4}"
fi
  
CA_STR=""
case "${CA_TYPE}" in
        "letsencrypt")
                CA_STR="--server letsencrypt"
                ;;

        "zerossl")
                CA_STR="--server zerossl"
                ;;

        "buypass")
                CA_STR="--server https://api.buypass.com/acme/directory"
                ;;

esac


# 新注
if [ -n "${5}" ]; then
        if [ "${ACTION}" = "m3" ]; then
                ${COMMAND} acme.sh --server https://api.buypass.com/acme/directory --register-account  --accountemail ${EMAIL}
        else
                if [ -n "${CA_STR}" ]; then
                        ${COMMAND} acme.sh --register-account -m ${EMAIL} ${CA_STR}
                fi
        fi
fi


case "${ACTION}" in
        # 泛解析
        "m1")
                ${COMMAND} --issue --dns ${DNS_TYPE} -d ${DOMAIN} -d *.${DOMAIN} --keylength ec-256 --ecc --force ${CA_STR}
                ;;

        # 非泛解析
        "m2")
                ${COMMAND} --issue --dns ${DNS_TYPE} -d ${DOMAIN} --keylength ec-256 --ecc --force ${CA_STR}
                ;;

        # 非泛解析，170天，Wildcard not supported
        "m3")
                ${COMMAND} acme.sh --issue --dns ${DNS_TYPE} -d ${DOMAIN} --keylength ec-256 --ecc --force ${CA_STR} --days 170
                ;;
esac

${COMMAND} --install-cert --ecc -d ${DOMAIN} --key-file /data/ssl/${DOMAIN}.key --fullchain-file /data/ssl/${DOMAIN}.fullchain.cer
