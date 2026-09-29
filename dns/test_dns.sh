#!/usr/bin/env bash
# 测试传统公共 DNS 服务器（53 端口，UDP 优先、TCP 兜底）是否可用
# 适用于任何有正常公网出口的 Linux 机器（云端/本地均可）
#
# 用法：
#   bash test_dns.sh                       # IPv4，默认读取 ./.file_dns
#   bash test_dns.sh ./.file_other         # IPv4，指定其他清单
#   bash test_dns.sh -6                    # IPv6，默认读取 ./.file_dns6
#   bash test_dns.sh --ipv6 ./.file_dns6_other
#
# 参数：
#   -6 | --ipv6   切到 IPv6 模式：
#                   · 默认清单改为 ./.file_dns6
#                   · 结果文件改为 dns6_ok.txt / dns6_fail.txt
#                   · 底层用 IPv6 套接字 / dig 以 IPv6 服务器地址查询
#   其余位置参数为清单文件路径
#
# 依赖：dig（推荐）；若缺失则自动回退到 python3 socket（UDP）
# 注意：本脚本不含代理设置，请在能直连公网的机器上运行
# 清单格式：每行「名称|地址1,地址2」；# 开头与空行忽略
# 输出：<前缀>_ok.txt 与源清单格式一致，每行「名称|可用地址1,可用地址2」
#       （只保留测试通过的 IP，按清单原有顺序聚合，可直接复用为清单）
#       不可用写入 <前缀>_fail.txt（运行前清空重写）
#       终端回显上色：✅ 成功=绿，⚠️ 软失败=黄，❌ 失败=红

set -uo pipefail

# ---- 解析参数 ----
IPV6=0
POS=()
for a in "$@"; do
  case "${a}" in
    -6|--ipv6) IPV6=1 ;;
    -h|--help)
      echo "用法: bash test_dns.sh [-6|--ipv6] [清单文件]"
      echo "  (无参数)  IPv4，默认读取 ./.file_dns"
      echo "  -6/--ipv6 IPv6，默认读取 ./.file_dns6"
      exit 0 ;;
    *) POS+=("${a}") ;;
  esac
done

if [ "${IPV6}" = 1 ]; then
  DEF_LIST=".file_dns6"; OK_FILE="dns6_ok.txt"; FAIL_FILE="dns6_fail.txt"
  FAMILY="AF_INET6"; MODE="IPv6"
else
  DEF_LIST=".file_dns";  OK_FILE="dns_ok.txt";  FAIL_FILE="dns_fail.txt"
  FAMILY="AF_INET";  MODE="IPv4"
fi

# 成功 / 失败结果分别写入这两个文件（运行前清空，避免历史残留）
: > "${OK_FILE}"
: > "${FAIL_FILE}"

# ---- 终端颜色 ----
RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; NC=$'\033[0m'

# 如需测试其他域名，修改下面这一行（国内服务器建议同时测一个国内域名，如 www.qq.com）
DOMAIN="example.com"

# 待测试清单：默认读取 DEF_LIST，可经由位置参数指定其他文件
LIST_FILE="${POS[0]:-${DEF_LIST}}"
if [ ! -f "${LIST_FILE}" ]; then
  echo "错误：清单文件不存在 -> ${LIST_FILE}"
  echo "用法：bash test_dns.sh [-6|--ipv6] [清单文件]"
  echo "清单格式：每行「名称|地址1,地址2」，# 开头为注释行"
  exit 1
fi
# 读取清单（逐行读取，跳过空行与 # 注释行；避免使用进程替换以兼容更多环境）
SERVERS=()
while IFS= read -r line || [ -n "${line}" ]; do
  case "${line}" in
    ''|\#*) continue ;;
    *) SERVERS+=("${line}") ;;
  esac
done < "${LIST_FILE}"
if [ "${#SERVERS[@]}" -eq 0 ]; then
  echo "错误：清单文件 ${LIST_FILE} 为空或不包含有效条目"
  exit 1
fi
echo "模式: ${MODE}  |  清单文件: ${LIST_FILE}（共 ${#SERVERS[@]} 个待测试服务商）"

# 判断 dig 输出是否为错误（超时/不可达等），是则返回空
clean_dig() {
  local out="$1"
  if echo "${out}" | grep -qiE 'communications error|timed out|connection refused|no servers could be reached|host unreachable|network unreachable'; then
    return 1
  fi
  echo "${out}" | grep -vE '^;' | grep -v '^$' | head -1
  return 0
}

test_one() {
  local name="$1" ip="$2"
  local ans=""

  # 1) dig UDP
  if command -v dig >/dev/null 2>&1; then
    ans="$(clean_dig "$(dig @"${ip}" "${DOMAIN}" +short +time=5 +tries=2 2>/dev/null)")"
  fi
  # 2) dig TCP 兜底
  if [ -z "${ans}" ] && command -v dig >/dev/null 2>&1; then
    ans="$(clean_dig "$(dig @"${ip}" "${DOMAIN}" +tcp +short +time=5 +tries=2 2>/dev/null)")"
  fi
  # 3) python3 socket（UDP）兜底（按模式选 IPv4 / IPv6）
  if [ -z "${ans}" ] && command -v python3 >/dev/null 2>&1; then
    ans="$(python3 - "${ip}" "${DOMAIN}" "${FAMILY}" <<'PY'
import sys, socket, struct
ip, dom, fam = sys.argv[1], sys.argv[2], sys.argv[3]
af = socket.AF_INET6 if fam == "AF_INET6" else socket.AF_INET
def build(name):
    tid = b"\x12\x34"
    hdr = tid + b"\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00"
    qb = b"".join(bytes([len(x)]) + x.encode() for x in name.split(".")) + b"\x00"
    return hdr + qb + b"\x00\x01\x00\x01"
try:
    s = socket.socket(af, socket.SOCK_DGRAM, 0)
    s.settimeout(5)
    s.sendto(build(dom), (ip, 53))
    data, _ = s.recvfrom(4096)
    ancount = struct.unpack(">H", data[6:8])[0]
    print("有响应但无 A 记录" if ancount == 0 else "解析到 %d 条记录" % ancount)
except Exception as e:
    print("失败: %s" % e)
PY
)"
  fi

  # 判定并回传：0=可用（输出 IP），1=不可用（输出详情）
  if [ -z "${ans}" ] || echo "${ans}" | grep -q '失败'; then
    local detail="${ans:-超时/不可达}"
    echo "${RED}  [${ip}] ❌ ${detail}${NC}"
    echo "${name} | ${ip} | ${detail}" >> "${FAIL_FILE}"
  elif echo "${ans}" | grep -q '无 A 记录'; then
    echo "${YELLOW}  [${ip}] ⚠️ ${ans}（仅响应但不返回解析结果，实用性存疑）${NC}"
  else
    echo "${GREEN}  [${ip}] ✅ 可用 -> ${ans}${NC}"
    return 0
  fi
  return 1
}

echo "测试域名: ${DOMAIN}（若需更换，改脚本顶部 DOMAIN 变量）"
for entry in "${SERVERS[@]}"; do
  name="${entry%%|*}"
  ips="${entry##*|}"
  echo "== ${name} =="
  IFS=',' read -ra arr <<< "${ips}"
  ok_ips=()
  for ip in "${arr[@]}"; do
    if test_one "${name}" "${ip}"; then
      ok_ips+=("${ip}")
    fi
  done
  # 有可用 IP 才写入 ok 文件，格式与源清单一致：名称|地址1,地址2
  if [ "${#ok_ips[@]}" -gt 0 ]; then
    echo "${name}|$(IFS=','; echo "${ok_ips[*]}")" >> "${OK_FILE}"
  fi
done

# ---- 结果汇总 ----
echo "========================================"
echo "测试完成（${MODE}）。"
echo "可用（${OK_FILE}）：${GREEN}${OK_FILE}（$(wc -l < "${OK_FILE}" | tr -d ' ') 条）${NC}"
echo "不可用（${FAIL_FILE}）：${RED}${FAIL_FILE}（$(wc -l < "${FAIL_FILE}" | tr -d ' ') 条）${NC}"
