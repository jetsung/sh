#!/usr/bin/env bash
# 测试 DoH（DNS-over-HTTPS, RFC 8484）端点是否可用
# 用法：
#   bash test_doh.sh                       # 默认读取 ./.file_doh 清单（每行一个 DoH URL）
#   bash test_doh.sh ./.file_doh_other     # 指定其他清单文件
#   bash test_doh.sh https://doh.pub/dns-query   # 直接传入单个 DoH URL
# 依赖：curl、python3（生成/解析 DNS 报文）
# 注意：本脚本不含代理设置，请在能直连公网的机器上运行（或 export https_proxy=...）
# 输出：成功端点写入 doh_ok.txt，失败端点写入 doh_fail.txt（均位于当前目录）

set -uo pipefail

# 成功 / 失败结果分别写入这两个文件（运行前清空，避免历史残留）
OK_FILE="doh_ok.txt"
FAIL_FILE="doh_fail.txt"
: > "${OK_FILE}"
: > "${FAIL_FILE}"

# ---- 终端颜色（失败/成功状态码上色）----
RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; NC=$'\033[0m'
# color_code <http码> <get|post>  -> 返回带色的码字符串
#   2xx          : 绿（成功）
#   GET 的 3xx   : 黄（仅提示，本脚本 GET 不跟随重定向，非失败）
#   其余(4xx/5xx/000/POST 的 3xx) : 红（失败）
color_code() {
  local code="$1" kind="$2"
  case "${code}" in
    2*)  printf '%s' "${GREEN}${code}${NC}" ;;
    000) printf '%s' "${RED}${code}${NC}" ;;
    3*)
      if [ "${kind}" = "post" ]; then printf '%s' "${RED}${code}${NC}"
      else printf '%s' "${YELLOW}${code}${NC}"; fi ;;
    *)   printf '%s' "${RED}${code}${NC}" ;;
  esac
}

# 单个请求超时（秒），避免某个端点卡死整批
CONN_TIMEOUT=5
MAX_TIME=10

# 生成 DNS 查询报文（查询 example.com 的 A 记录），供 POST 与 GET 共用
make_query() {
  python3 -c 'import sys;sys.stdout.buffer.write(b"\x12\x34\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x07example\x03com\x00\x00\x01\x00\x01")'
}

# 解析 DoH 返回的二进制报文，提取 A 记录。
# 关键修复：响应可能不是 DNS 报文（如 301 重定向返回的 HTML 页），
# 此时不再解析长度/计数字段，避免 IndexError；改为宽松校验后安全退出。
parse_resp() {
  python3 - "$1" <<'PY'
import sys, struct, socket
b = open(sys.argv[1], "rb").read()
if len(b) < 12:
    print("（响应过短，疑似非 DNS 报文 / 重定向页）"); sys.exit(0)
# DNS 响应报文特征：第 2 字节最高位为 QR 位（=1 表示响应）
if not (b[2] & 0x80):
    print("（响应非 DNS 报文，疑似 HTML / 重定向页；前 64 字节：）")
    print("  " + b[:64].hex(" "))
    sys.exit(0)
ancount = struct.unpack(">H", b[6:8])[0]
print("Answer 记录数:", ancount)

def skip_name(i):
    # 遍历一个域名（支持压缩指针），越界立即抛出
    while True:
        if i >= len(b):
            raise ValueError("name 越界")
        if b[i] == 0:
            return i + 1
        if (b[i] & 0xc0) == 0xc0:
            if i + 2 > len(b):
                raise ValueError("压缩指针越界")
            return i + 2
        i += b[i] + 1

try:
    i = skip_name(12); i += 4
    ips = []
    for _ in range(ancount):
        i = skip_name(i)
        rtype, _rclass, _ttl, rdlen = struct.unpack(">HHIH", b[i:i+10]); i += 10
        rdata = b[i:i+rdlen]; i += rdlen
        if rtype == 1 and rdlen == 4:
            ips.append(socket.inet_ntoa(rdata))
    if ips:
        print("解析到的 A 记录:", ", ".join(ips))
    else:
        print("（无 A 记录；响应前 32 字节：）")
        print("  " + b[:32].hex(" "))
except Exception:
    print("（响应结构异常，可能无法解析为 DNS；前 64 字节：）")
    print("  " + b[:64].hex(" "))
PY
}

test_doh() {
  local DOH_URL="$1"
  local QBIN RBIN
  QBIN="$(mktemp /tmp/doh_query.XXXXXX.bin)"
  RBIN="$(mktemp /tmp/doh_resp.XXXXXX.bin)"
  trap 'rm -f "$QBIN" "$RBIN"' RETURN

  make_query > "$QBIN"
  local DNS_B64
  DNS_B64="$(python3 -c 'import base64,sys;print(base64.urlsafe_b64encode(open(sys.argv[1],"rb").read()).decode().rstrip("="))' "$QBIN")"

  echo ">>> 测试 DoH 端点: ${DOH_URL}"

  # GET 方式（DNS 报文做 base64url 编码后作为参数）
  # 注：不跟随重定向，避免丢失 ?dns= 参数；301 仅作信息展示。
  local get_code
  get_code=$(curl -s --connect-timeout "${CONN_TIMEOUT}" --max-time "${MAX_TIME}" \
    -o /dev/null -w "%{http_code}" \
    -H "accept: application/dns-message" \
    "${DOH_URL}?dns=${DNS_B64}" 2>/dev/null)
  [ -z "${get_code}" ] && get_code="000"
  echo "GET  HTTP $(color_code "${get_code}" get)"

  # POST 方式（标准推荐：直接发送 DNS 报文二进制）
  # 跟随重定向（-L）并在 301/302/303 后保持 POST（--post30x），
  # 这样像 CleanBrowsing 这类旧端点 301 跳转到新地址时仍能正确测试。
  local post_line
  post_line=$(curl -sL --post301 --post302 --post303 \
    --connect-timeout "${CONN_TIMEOUT}" --max-time "${MAX_TIME}" \
    -H "content-type: application/dns-message" -H "accept: application/dns-message" \
    --data-binary "@${QBIN}" \
    "${DOH_URL}" -o "$RBIN" -w "%{http_code} %{size_download} %{content_type}" 2>/dev/null)
  [ -z "${post_line}" ] && post_line="000 0 "
  local post_code size ctype
  read -r post_code size ctype <<< "${post_line}"
  echo "POST HTTP $(color_code "${post_code}" post), ${size}B, type=${ctype}"

  # 解析返回（已加固，不会因非 DNS 响应而崩溃）
  local parsed
  parsed="$(parse_resp "$RBIN")"
  echo "${parsed}"

  # 判定成功：POST 返回 200 且解析到 A 记录
  if [ "${post_code}" = "200" ] && echo "${parsed}" | grep -q "解析到的 A 记录"; then
    echo "${DOH_URL}" >> "${OK_FILE}"
  else
    echo "${DOH_URL} | GET=${get_code} POST=${post_code} type=${ctype} | ${parsed}" >> "${FAIL_FILE}"
  fi
}

# ---- 解析待测清单 ----
URLS=()
if [ -n "${1:-}" ] && [ -f "${1:-}" ]; then
  # 参数是一个存在的文件 -> 逐行读取 DoH URL（跳过空行与 # 注释行）
  while IFS= read -r line || [ -n "${line}" ]; do
    case "${line}" in
      ''|\#*) continue ;;
      *) URLS+=("${line}") ;;
    esac
  done < "${1}"
  echo "清单文件: ${1}（共 ${#URLS[@]} 个 DoH 端点）"
elif [ -n "${1:-}" ]; then
  # 参数不是文件 -> 视为单个 DoH URL
  URLS=("${1}")
elif [ -f ./.file_doh ]; then
  # 默认读取 ./.file_doh
  while IFS= read -r line || [ -n "${line}" ]; do
    case "${line}" in
      ''|\#*) continue ;;
      *) URLS+=("${line}") ;;
    esac
  done < ./.file_doh
  echo "清单文件: ./.file_doh（共 ${#URLS[@]} 个 DoH 端点）"
else
  # 兜底：默认 DNSPod 公共 DNS
  URLS=("https://doh.pub/dns-query")
  echo "未指定清单，使用默认 DoH 端点：https://doh.pub/dns-query"
fi

for u in "${URLS[@]}"; do
  test_doh "${u}"
  echo
done

# ---- 结果汇总 ----
echo "========================================"
echo "测试完成。"
echo "可用端点（${OK_FILE}）：${GREEN}${OK_FILE}（$(wc -l < "${OK_FILE}" | tr -d ' ') 个）${NC}"
echo "不可用端点（${FAIL_FILE}）：${RED}${FAIL_FILE}（$(wc -l < "${FAIL_FILE}" | tr -d ' ') 个）${NC}"
