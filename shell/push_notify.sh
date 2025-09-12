#!/usr/bin/env bash

#============================================================
# File: push_notify.sh
# Description: 推送消息到钉钉、飞书、Lark
# URL: https://fx4.cn/
# ORIGIN: https://gist.asfd.cn/jetsung/notify/raw/HEAD/notify.sh
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2025-08-18
# UpdatedAt: 2025-08-18
#============================================================


if [[ -n "${DEBUG:-}" ]]; then
    set -eux
else
    set -euo pipefail
fi

judgment_parameters() {
  while [[ "$#" -gt '0' ]]; do
    case "$1" in
    '-h' | '--help')
      HELP='1'
      break
      ;;
    -m | --message)
      if [[ -z "${2:?error: Please specify the correct message.}" ]]; then
        exit 1
      fi
      MESSAGE="$2"
      shift
      ;;
    -s | --secret)
      if [[ -z "${2:?error: Please specify the correct secret.}" ]]; then
        exit 1
      fi
      SECRET="$2"
      shift
      ;;
    -t | --timestamp)
      if [[ -z "${2:?error: Please specify the correct timestamp.}" ]]; then
        exit 1
      fi
      TIMESTAMP="$2"
      shift
      ;;
    -u | --url)
      if [[ -z "${2:?error: Please specify the correct url.}" ]]; then
        exit 1
      fi
      URL="$2"
      shift
      ;;
    *)
      echo "$0: unknown option -- -"
      exit 1
      ;;
    esac
    shift
  done
}

show_help() {
  echo "usage: $0 [ options ]"
  echo '  -h, --help      Show help'
  echo '  -m, --message   Push message'
  echo '  -s, --secret    Push secret'
  echo '  -t, --timestamp Push timestamp'
  echo '  -u, --url       Push url'
  exit 0
}

send_message() {
  SEND_TEMPLATE_DINGTALK='{
  "msgtype": "text",
  "text": {
    "content": "消息通知： %s "
  },
  "at": {
    "isAtAll": false
  }
}'

  SEND_TEMPLATE_FEISHU='{
                "msg_type": "text",
                "content": {"text": "消息通知: %s "},
                "sign": "%s",
                "timestamp": %d
        }'

  # shellcheck disable=SC2059
  if [[ "$DOMAIN" == "oapi.dingtalk.com" ]]; then
    [[ ${#TIMESTAMP} -eq 13 ]] || TIMESTAMP="${TIMESTAMP}000"
    signature 1
    message=$(printf "$SEND_TEMPLATE_DINGTALK" "$MESSAGE")
    URL=$(printf "${URL}&timestamp=%s&sign=%s" "$TIMESTAMP" "$SIGN")
  else
    signature 2
    message=$(printf "$SEND_TEMPLATE_FEISHU" "$MESSAGE" "$SIGN" "$TIMESTAMP")
  fi

  curl -XPOST -s -L "$URL" -H "Content-Type:application/json" -H "charset:utf-8" -d "$message"
}

signature() {
  if [[ -z "${SECRET:-}" ]]; then
    SIGN=""
    return
  fi

  string_to_sign="${TIMESTAMP}\n${SECRET}"

  if [[ "${1:-1}" == 1 ]]; then
    sign_str="$SECRET"
    data="$string_to_sign"
  else
    sign_str="$string_to_sign"
    data=""
  fi

  TMPPATH=$(mktemp "/tmp/notify.XXXXXX")

  clearup() {
    rm -rf "$TMPPATH"
  }
  trap clearup EXIT

  # shellcheck disable=SC2059
  printf "$sign_str" >"$TMPPATH"
  # shellcheck disable=SC2059
  SIGN=$(printf "$data" | openssl dgst -sha256 -hmac "$(cat "$TMPPATH")" -binary | base64)
}

main() {
  judgment_parameters "$@"

  [[ "${HELP:-}" -eq '1' ]] && show_help

  if [[ -z "$MESSAGE" ]]; then
    echo "error: Please specify the correct message."
    exit 1
  fi

  if [[ -z "$URL" ]]; then
    echo "error: Please specify the correct url."
    exit 1
  fi

  DOMAIN=$(echo "$URL" | awk -F[/:] '{print $4}')
  if [[ "$DOMAIN" != "oapi.dingtalk.com" ]] &&
    [[ "$DOMAIN" != "open.feishu.cn" ]] &&
    [[ "$DOMAIN" != "open.larksuite.com" ]]; then
    echo "error: Please specify the correct url."
    exit 1
  fi

  [[ -n "${TIMESTAMP:-}" ]] || TIMESTAMP="$(date +%s)"

  send_message
}

main "$@"
