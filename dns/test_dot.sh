#!/usr/bin/env bash
# 测试 DoT（DNS-over-TLS, RFC 7858）主机名是否可用
# 用法：
#   bash test_dot.sh                  # 默认读取 ./.file_dot 清单（每行一个 DoT 主机名）
#   bash test_dot.sh ./.file_dot_other    # 指定其他清单文件
#   bash test_dot.sh dot.pub           # 直接传入单个 DoT 主机名
# 依赖：python3（标准库 ssl 即可，无需特殊 dig 版本）
# 注意：本脚本不含代理设置，请在能直连公网的机器上运行
# 输出：
#   可用主机写入 dot_ok.txt，不可用主机写入 dot_fail.txt（均位于当前目录，运行前清空重写）
#   终端回显按结果上色：✅ 成功=绿，⚠️ 软失败=黄，❌ 失败=红

set -uo pipefail

# 成功 / 失败结果分别写入这两个文件（运行前清空，避免历史残留）
OK_FILE="dot_ok.txt"
FAIL_FILE="dot_fail.txt"
: > "${OK_FILE}"
: > "${FAIL_FILE}"

# ---- 终端颜色（结果状态上色）----
RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; NC=$'\033[0m'

# 待测试域名（国内服务器建议同时把下面 DOMAIN 改成 www.qq.com 一起测）
DOMAIN="example.com"

test_dot() {
  local HOST="$1"
  echo ">>> 测试 DoT 主机: ${HOST}"
  # 脚本已用 set -uo pipefail（未启用 errexit），python 异常被内部 except 捕获并返回非 0
  # 也不会中断整批；这里把 python 输出整体捕获后再判定
  local result
  result="$(python3 - "${HOST}" "${DOMAIN}" <<'PY'
import sys, socket, ssl, struct
host, dom = sys.argv[1], sys.argv[2]

def build_query(name):
    tid = b"\x12\x34"
    hdr = tid + b"\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00"
    qb = b"".join(bytes([len(x)]) + x.encode() for x in name.split(".")) + b"\x00"
    return hdr + qb + b"\x00\x01\x00\x01"

def recv_exact(sock, n):
    data = b""
    while len(data) < n:
        chunk = sock.recv(n - len(data))
        if not chunk:
            break
        data += chunk
    return data

try:
    q = build_query(dom)
    ctx = ssl.create_default_context()
    with socket.create_connection((host, 853), timeout=8) as sock:
        with ctx.wrap_socket(sock, server_hostname=host) as ss:
            ss.sendall(len(q).to_bytes(2, "big") + q)
            length = struct.unpack(">H", ss.recv(2))[0]
            data = recv_exact(ss, length)
    ancount = struct.unpack(">H", data[6:8])[0]
    if ancount > 0:
        def skip_name(i):
            while data[i] != 0:
                if data[i] & 0xc0 == 0xc0:
                    return i + 2
                i += data[i] + 1
            return i + 1
        i = skip_name(12); i += 4
        ips = []
        for _ in range(ancount):
            i = skip_name(i)
            rtype, _rc, _ttl, rdlen = struct.unpack(">HHIH", data[i:i+10]); i += 10
            rdata = data[i:i+rdlen]; i += rdlen
            if rtype == 1 and rdlen == 4:
                ips.append(socket.inet_ntoa(rdata))
        if ips:
            print("  ✅ 可用 -> 返回 %d 条记录（A: %s）" % (ancount, ", ".join(ips)))
        else:
            print("  ⚠️ 有响应但无 A 记录（%d 条）" % ancount)
    else:
        print("  ⚠️ 有响应但无 A 记录（0 条）")
except Exception as e:
    print("  ❌ 失败: %s" % e)
PY
)"
  # 判定 + 上色 + 落盘（✅→绿/OK_FILE，⚠️→黄/FAIL_FILE，其余→红/FAIL_FILE）
  local line="${result#"  "}"
  if printf '%s' "${result}" | grep -q "✅"; then
    echo "${GREEN}${result}${NC}"
    echo "${HOST}" >> "${OK_FILE}"
  elif printf '%s' "${result}" | grep -q "⚠️"; then
    echo "${YELLOW}${result}${NC}"
    echo "${HOST} | ${line}" >> "${FAIL_FILE}"
  else
    echo "${RED}${result}${NC}"
    echo "${HOST} | ${line}" >> "${FAIL_FILE}"
  fi
}

# ---- 解析待测清单 ----
HOSTS=()
if [ -n "${1:-}" ] && [ -f "${1:-}" ]; then
  while IFS= read -r line || [ -n "${line}" ]; do
    case "${line}" in
      ''|\#*) continue ;;
      *) HOSTS+=("${line}") ;;
    esac
  done < "${1}"
  echo "清单文件: ${1}（共 ${#HOSTS[@]} 个 DoT 主机）"
elif [ -n "${1:-}" ]; then
  HOSTS=("${1}")
elif [ -f ./.file_dot ]; then
  while IFS= read -r line || [ -n "${line}" ]; do
    case "${line}" in
      ''|\#*) continue ;;
      *) HOSTS+=("${line}") ;;
    esac
  done < ./.file_dot
  echo "清单文件: ./.file_dot（共 ${#HOSTS[@]} 个 DoT 主机）"
else
  # 兜底：列出 5 个已知 DoT 主机
  HOSTS=(dot.pub dns.google one.one.one.one dns.quad9.net dns.alidns.com)
  echo "未指定清单，使用内置 5 个 DoT 主机"
fi

for h in "${HOSTS[@]}"; do
  test_dot "${h}"
  echo
done

# ---- 结果汇总 ----
echo "========================================"
echo "测试完成。"
echo "可用主机（${OK_FILE}）：${GREEN}${OK_FILE}（$(wc -l < "${OK_FILE}" | tr -d ' ') 个）${NC}"
echo "不可用主机（${FAIL_FILE}）：${RED}${FAIL_FILE}（$(wc -l < "${FAIL_FILE}" | tr -d ' ') 个）${NC}"
