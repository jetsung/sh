#!/usr/bin/env bash

#============================================================
# File: webui.sh
# Description: pi / omp / cbc / dsh / atomcode 的 WebUI 管理（纯终端启停，不使用 systemd）
# URL: https://fx4.cn/webui
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2026-09-09
# UpdatedAt: 2026-09-09
#============================================================

# pi / omp / cbc / dsh / atomcode 的 WebUI —— 纯终端启停（不使用 systemd）
#
#   webui start [名]  启动（默认全部）；名 = pi|omp|cbc|dsh|atomcode
#   webui stop  [名]  停止
#   webui restart [名] 重启
#   webui status              查看运行状态
#   webui url                 打印访问地址
#   webui log <名>            跟踪日志
#
# 全部服务固定免密运行（家用局域网，认证交给外层 nginx 反代）。
#
# cbc：CodeBuddy CLI 的隔离启动逻辑已内联（不依赖外部文件），
# 用 `codebuddy --serve --auth none` 起自带 Web UI，端口 30140。
#
# dsh：DeepSeek Harness 的 Web profile（`dsh web`），端口 30143。
# atomcode：AtomCode 自带 webui（`atomcode webui`），端口 30144。
# 注意：dsh / atomcode 的 URL token 是二进制内置强制（无关闭选项），
# 首次访问需带 token 换 cookie；token 可用 `webui pass` 查看。
#
# 为什么不走 systemd：systemd user 服务不读 ~/.zshrc / ~/.zprofile，PATH 里
# 缺 ~/.bun/bin，WebUI 调不到 omp / pi 二进制（模型列表、会话命名都依赖它），
# 表现为界面能开但选不了模型。这里统一用登录式 shell 启动，完整继承终端环境。
if [[ -n "${DEBUG:-}" ]]; then
    set -eux
else
    set -euo pipefail
fi

LOGDIR="$HOME/.local/log"
RUNDIR="$HOME/.local/run"
# 所有 WebUI 服务的统一工作目录
WORKDIR="${WORKDIR:-$HOME/vibedir}"
mkdir -p "$LOGDIR" "$RUNDIR" "$WORKDIR"

# pi-web / omp-web / dsh / atomcode 直接用命令名，由登录 shell 的 PATH 解析
# （.zshrc 里 fnm/bun 已内置）；进程命令行匹配串：
PI_PAT='[p]i-web --hostname'
OMP_PAT='[o]mp-web --hostname'

# cbc = CodeBuddy 隔离启动器（逻辑内联自 ~/.local/bin/cbs），--serve 自带 Web UI。
# 进程经 exec 后命令行是 <node> .../codebuddy --serve --host 0.0.0.0 --port 30140 --auth none。
# 匹配到 --host 0.0.0.0 为止：WorkBuddy 内嵌 codebuddy（/opt/WorkBuddy/...）同样以
# `codebuddy --serve ...` 起进程但不带 --host，裸匹配会误判 cbc 已在运行。
CBC_PORT=30140
CBC_PAT='[c]odebuddy --serve --host 0.0.0.0'
# CodeBuddy 配置目录（与 WorkBuddy 的 ~/.workbuddy 完全隔离）
CBC_CONFIG_DIR="${CB_CONFIG_DIR:-$HOME/.codebuddy}"

# dsh = DeepSeek Harness（`dsh web`），命令名由 PATH 解析。
DSH_PORT=30143
# dsh 默认只绑 127.0.0.1，无需传 --host；进程匹配串相应放宽到 `dsh web`
DSH_PAT='[d]sh web'

# atomcode = AtomCode 自带 webui（`atomcode webui`）。token 保护，token 打在日志里。
AC_PORT=30144
AC_PAT='[a]tomcode webui'

# 登录 shell：继承 .zshrc/.zprofile 的 PATH、API key 等
LOGIN_SHELL="$(getent passwd "$(id -u)" | cut -d: -f7)"
[[ -x "$LOGIN_SHELL" ]] || LOGIN_SHELL="$(command -v zsh || command -v bash)"

lan_ip() {
  ip -4 addr show scope global 2>/dev/null \
    | awk '/inet /{print $2}' | cut -d/ -f1 | grep -v '^100\.' | head -1
}
LAN_IP="$(lan_ip)"; [[ -z "$LAN_IP" ]] && LAN_IP=127.0.0.1

# —— 颜色：运行中/URL 标签绿色、未运行红色（非 TTY 时自动退化为无色）——
if [[ -t 1 ]]; then
  C_RESET=$'\e[0m'; C_GREEN=$'\e[32m'; C_RED=$'\e[31m'
else
  C_RESET=''; C_GREEN=''; C_RED=''
fi

running() { pgrep -f "$1" >/dev/null; }
# pgrep 无匹配时退出码非零，|| true 抵消 pipefail，避免调用处被 set -e 波及
pids_of() { pgrep -f "$1" 2>/dev/null | tr '\n' ' ' || true; }

# 监听指定端口的进程 pid（取自 ss，最可靠——pid 文件/匹配串都可能抓到别的实例）。
# 端口无人监听时管道会以非零退出（pipefail），|| true 保证函数恒返回 0，
# 否则 set -e 会在 status 循环中途杀掉整个脚本。
port_pid() { # $1=端口
  ss -lntpH 2>/dev/null | awk -v p=":$1\$" '$4 ~ p' \
    | grep -o 'pid=[0-9]*' | cut -d= -f2 | sort -u | head -1 || true
}

start_one() { # $1=名 $2=bin(命令名) $3=端口 $4=匹配串 $5=启动参数 $6=可选:额外环境(如 BROWSER=/bin/false)
  local name="$1" bin="$2" port="$3" pat="$4" args="$5" extra_env="${6:-}"
  if running "$pat"; then
    echo "$name 已在运行 (pid: $(pids_of "$pat"))"
    return 0
  fi
  # bin 是命令名，由内层登录 shell（.zshrc 注入 fnm/bun 的 PATH）解析；
  # 外层仅校验非空。找不到时内层 exec 失败会写进日志，下方启动检查会报错退出。
  [[ -n "$bin" ]] || { echo "$name 启动失败：未指定可执行文件" >&2; return 1; }

  # setsid：脱离当前会话与进程组，否则父 shell 退出时进程会被一起回收
  # （nohup 挡不住 SIGKILL，实测会随会话结束消失）
  setsid "$LOGIN_SHELL" -lc "
    # 登录式非交互 shell 不会加载 ~/.zshrc，而 API key 是 ~/.envs 用 sqlite 载入的
    # （omp 的 models.json 里写的是 !echo -n \"\\\$SENSE_API_KEY\" 这类命令式取值，
    #  子进程继承不到变量就会拿到空密钥）。所以这里手动 source 一次。
    if [ -f '$HOME/.zshrc' ]; then
      . '$HOME/.zshrc' 2>/dev/null
    elif [ -f '$HOME/.bashrc' ]; then
      . '$HOME/.bashrc' 2>/dev/null
    fi
    [ -f '$HOME/.env' ] && . '$HOME/.env' 2>/dev/null
    $extra_env
    cd '$WORKDIR'
    exec '$bin' $args
  " </dev/null >> "$LOGDIR/$name.log" 2>&1 &
  local leader=$!
  disown 2>/dev/null || true

  # 记录进程组：WebUI 会 fork 子进程（omp -> bun，pi -> next-server）真正持有端口，
  # 只杀 launcher 会留下孤儿占着端口，下次启动报 EADDRINUSE
  local pgid; pgid="$(ps -o pgid= -p "$leader" 2>/dev/null | tr -d ' ')"
  [[ -n "$pgid" ]] || pgid="$leader"
  echo "$pgid" > "$RUNDIR/webui-$name.pid"

  for _ in $(seq 1 15); do
    sleep 1
    running "$pat" && break
  done
  if running "$pat"; then
    echo "$name 已启动 (pid: $(pids_of "$pat"))  日志 $LOGDIR/$name.log"
  else
    echo "$name 启动失败，看 $LOGDIR/$name.log" >&2
    return 1
  fi
}

stop_one() { # $1=名 $2=匹配串 $3=端口
  local port="$3"
  local pf="$RUNDIR/webui-$1.pid" pgid=""
  [[ -f "$pf" ]] && pgid="$(cat "$pf" 2>/dev/null || true)"

  if [[ -n "$pgid" ]] && kill -0 -- "-$pgid" 2>/dev/null; then
    # 负 PID = 整个进程组，连 fork 出去的子进程一起收掉
    kill -TERM -- "-$pgid" 2>/dev/null || true
    for _ in $(seq 1 10); do
      kill -0 -- "-$pgid" 2>/dev/null || break
      sleep 0.5
    done
    kill -0 -- "-$pgid" 2>/dev/null && kill -KILL -- "-$pgid" 2>/dev/null
  fi
  # 兜底：pid 文件失效时按命令行匹配清一遍（含 fork 出的子进程）
  pkill -f "$2" 2>/dev/null || true
  rm -f "$pf"

  # 最后兜底：按端口清理残留（fork 出去的 bun / next-server 命令行里没有关键字）。
  # 端口无人监听时 grep 无匹配会因 pipefail 使赋值非零，|| true 防 set -e 中断。
  local holder
  holder="$(ss -lntpH 2>/dev/null | awk -v p=":$port\$" '$4 ~ p {print $NF}' \
            | grep -o 'pid=[0-9]*' | cut -d= -f2 | sort -u || true)"
  if [[ -n "$holder" ]]; then
    # holder 是换行分隔的多个 pid，有意按空白拆分传给 kill
    # shellcheck disable=SC2086
    kill -TERM $holder 2>/dev/null || true
    sleep 1
    # shellcheck disable=SC2086
    kill -KILL $holder 2>/dev/null || true
  fi

  if running "$2"; then
    echo "$1 未能完全停止，仍存在: $(pids_of "$2")" >&2
  else
    echo "$1 已停止"
  fi
}

start_t() { # $1=目标
  case "${1:-all}" in
    pi)  start_one pi  pi-web  30141 "$PI_PAT"  "--hostname 0.0.0.0 --port 30141 --no-open" ;;
    omp) start_one omp omp-web 30142 "$OMP_PAT" "--hostname 0.0.0.0 --port 30142 --no-open" ;;
    cbc)
      # 定位 codebuddy：只按 PATH 解析，找不到直接报错退出（无兜底）
      local cb_bin
      cb_bin="$(command -v codebuddy 2>/dev/null || true)"
      [[ -n "$cb_bin" ]] || { echo "cbc 启动失败：PATH 中找不到 codebuddy" >&2; exit 1; }

      # 固定免密（家用局域网）：--auth none 关闭 codebuddy 自带 Web UI 的认证
      local serve_args="--serve --host 0.0.0.0 --port $CBC_PORT --auth none"

      # 复用 start_one 的通用流程：setsid + 登录 shell + 环境准备 + 日志/PID。
      # 差异点：codebuddy 由内联脚本 exec 启动，启动前需清掉 WorkBuddy（或外层
      # rc 文件）注入的 CODEBUDDY_* 变量，并指向独立配置目录 ~/.codebuddy。
      # 注意内层是 zsh（无 bash 的 compgen），用 printenv 列出环境变量名。
      mkdir -p "$WORKDIR" 2>/dev/null || true
      local name=cbc bin="$LOGIN_SHELL"
      if running "$CBC_PAT"; then
        echo "$name 已在运行 (pid: $(pids_of "$CBC_PAT"))"
        return 0
      fi
      setsid "$bin" -lc "
        # 清掉外层注入的 CODEBUDDY_* 变量（与 WorkBuddy 的 ~/.workbuddy 隔离）
        while IFS= read -r _v; do unset \"\$_v\"; done < <(printenv | sed -n 's/^CODEBUDDY_\([A-Za-z0-9_]*\)=.*/\1/p')
        export CODEBUDDY_CONFIG_DIR='$CBC_CONFIG_DIR'
        if [ -f '$HOME/.zshrc' ]; then
          . '$HOME/.zshrc' 2>/dev/null
        elif [ -f '$HOME/.bashrc' ]; then
          . '$HOME/.bashrc' 2>/dev/null
        fi
        [ -f '$HOME/.env' ] && . '$HOME/.env' 2>/dev/null
        # rc 文件可能注入 CODEBUDDY_* 或覆盖配置目录，清一次再导出
        while IFS= read -r _v; do unset \"\$_v\"; done < <(printenv | sed -n 's/^CODEBUDDY_\([A-Za-z0-9_]*\)=.*/\1/p')
        export CODEBUDDY_CONFIG_DIR='$CBC_CONFIG_DIR'
        cd '$WORKDIR'
        exec '$cb_bin' $serve_args
      " </dev/null >> "$LOGDIR/$name.log" 2>&1 &
      local leader=$!
      disown 2>/dev/null || true
      local pgid; pgid="$(ps -o pgid= -p "$leader" 2>/dev/null | tr -d ' ')"
      [[ -n "$pgid" ]] || pgid="$leader"
      echo "$pgid" > "$RUNDIR/webui-$name.pid"
      for _ in $(seq 1 15); do
        sleep 1
        running "$CBC_PAT" && break
      done
      if running "$CBC_PAT"; then
        echo "$name 已启动 (pid: $(pids_of "$CBC_PAT"))  日志 $LOGDIR/$name.log"
      else
        echo "$name 启动失败，看 $LOGDIR/$name.log" >&2
        return 1
      fi
      ;;
    dsh)
      # dsh 内置只绑 127.0.0.1（无 --host 选项/不需要传）；
      # 局域网/远程访问请套 nginx 反代或 SSH 隧道
      start_one dsh dsh "$DSH_PORT" "$DSH_PAT" \
        "web --port $DSH_PORT --no-open"
      ;;
    atomcode)
      # BROWSER=/bin/false：atomcode webui 无 --no-open 参数，
      # 用空 BROWSER 让其 xdg-open 失败，不弹浏览器窗口
      start_one atomcode atomcode "$AC_PORT" "$AC_PAT" \
        "webui --host 0.0.0.0 --port $AC_PORT --no-telemetry" \
        "export BROWSER=/bin/false"
      ;;
    # 逐个启动；单渠道失败（返回 1）不应中止其余渠道，故逐个 || true。
    # start_t 内部有自己的报错输出，失败原因已在 stderr 展示。
    all)
      start_t pi      || true
      start_t omp     || true
      start_t cbc     || true
      start_t dsh     || true
      start_t atomcode || true
      ;;
    *) echo "用法: webui start [pi|omp|cbc|dsh|atomcode]" >&2; exit 2 ;;
  esac
}

stop_t() { # $1=目标
  case "${1:-all}" in
    pi)  stop_one pi  "$PI_PAT"  30141 ;;
    omp) stop_one omp "$OMP_PAT" 30142 ;;
    cbc) stop_one cbc "$CBC_PAT" "$CBC_PORT" ;;
    dsh) stop_one dsh "$DSH_PAT" "$DSH_PORT" ;;
    atomcode) stop_one atomcode "$AC_PAT" "$AC_PORT" ;;
    all) stop_t pi; stop_t omp; stop_t cbc; stop_t dsh; stop_t atomcode ;;
    *) echo "用法: webui stop [pi|omp|cbc|dsh|atomcode]" >&2; exit 2 ;;
  esac
}

token_note() { # $1=pi|omp|cbc|dsh|atomcode —— 取当前 token（无则空）
  case "$1" in
    dsh|atomcode)
      # 这两个的 URL token 是二进制内置强制（无关闭选项）
      sed -n 's/.*[?&]token=\([A-Za-z0-9._-]*\).*/\1/p' "$LOGDIR/$1.log" 2>/dev/null | tail -1
      ;;
  esac
}

# 完整访问 URL：带 token 的服务（dsh / atomcode）直接拼进 query，可直接点击使用
webui_url() { # $1=名 $2=host $3=端口
  local u="http://$2:$3" tv
  tv="$(token_note "$1")"
  [[ -n "$tv" ]] && u+="?token=$tv"
  printf '%s' "$u"
}

case "${1:-status}" in
  start)   start_t "${2:-all}" ;;
  stop)    stop_t   "${2:-all}" ;;
  restart) stop_t "${2:-all}"; sleep 1; start_t "${2:-all}" ;;
  status)
    for n in pi omp cbc dsh atomcode; do
      # dsh 只允许绑 127.0.0.1（不支持 --host 0.0.0.0），URL 也随之用本机回环
      host="$LAN_IP"
      if [[ "$n" == pi ]]; then pat="$PI_PAT"; port=30141;
      elif [[ "$n" == omp ]]; then pat="$OMP_PAT"; port=30142;
      elif [[ "$n" == cbc ]]; then pat="$CBC_PAT"; port="$CBC_PORT";
      elif [[ "$n" == dsh ]]; then pat="$DSH_PAT"; port="$DSH_PORT"; host=127.0.0.1;
      else pat="$AC_PAT"; port="$AC_PORT"; fi
      if running "$pat"; then
        # pid 取端口持有者（ss），避免匹配串抓到同命令行的其它实例
        spid="$(port_pid "$port")"
        # 已启用：整行绿色（服务名 + 状态）
        echo "${C_GREEN}$n WebUI: 运行中${C_RESET}"
        echo "    pid : $spid"
        echo "    url : $(webui_url "$n" "$host" "$port")"
      else
        # 未启用：整行红色
        echo "${C_RED}$n WebUI: 未运行${C_RESET}"
      fi
    done ;;
  url)
    for n in pi omp cbc dsh atomcode; do
      # dsh 只绑 127.0.0.1，URL 用本机回环
      host="$LAN_IP"
      if [[ "$n" == pi ]]; then pat="$PI_PAT"; port=30141;
      elif [[ "$n" == omp ]]; then pat="$OMP_PAT"; port=30142;
      elif [[ "$n" == cbc ]]; then pat="$CBC_PAT"; port="$CBC_PORT";
      elif [[ "$n" == dsh ]]; then pat="$DSH_PAT"; port="$DSH_PORT"; host=127.0.0.1;
      else pat="$AC_PAT"; port="$AC_PORT"; fi
      # 未运行的服务不输出 URL（日志里的历史 token 也随之失效，不再展示）
      running "$pat" || continue
      printf '%s %s\n' "${C_GREEN}$n url :${C_RESET}" "$(webui_url "$n" "$host" "$port")"
    done ;;
  token) # dsh/atomcode 的 token 每次启动随机生成（二进制内置，不可自定义）
    case "${2:-}" in
      dsh|atomcode)
        # token 属于当前运行实例：服务停止后历史日志里的 token 已失效，不再展示
        if [[ "$2" == dsh ]]; then pat="$DSH_PAT"; else pat="$AC_PAT"; fi
        if ! running "$pat"; then echo "$2 未运行，无有效 token" >&2; exit 1; fi
        v="$(sed -n 's/.*[?&]token=\([A-Za-z0-9._-]*\).*/\1/p' "$LOGDIR/$2.log" 2>/dev/null | tail -1)"
        if [[ -n "$v" ]]; then echo "$v"; else echo "$2 的 token 未找到（未启动过）" >&2; exit 1; fi
        ;;
      # 裸 token：与 url 一致，未运行的服务整行跳过
      "") for tn in dsh atomcode; do
            if [[ "$tn" == dsh ]]; then tpat="$DSH_PAT"; else tpat="$AC_PAT"; fi
            running "$tpat" || continue
            tv="$(sed -n 's/.*[?&]token=\([A-Za-z0-9._-]*\).*/\1/p' "$LOGDIR/$tn.log" 2>/dev/null | tail -1)"
            [[ -n "$tv" ]] && printf '%s %s\n' "${C_GREEN}$(printf '%-9s' "$tn") token :${C_RESET}" "$tv"
          done ;;
      *) echo "用法: webui token [dsh|atomcode]" >&2; exit 2 ;;
    esac ;;
  log)
    case "${2:-}" in
      pi|omp|cbc|dsh|atomcode) tail -f "$LOGDIR/$2.log" ;;
      *) echo "用法: webui log <pi|omp|cbc|dsh|atomcode>" >&2; exit 2 ;;
    esac ;;
  *)
    echo "用法: webui start|stop|restart|status|url|token|log [pi|omp|cbc|dsh|atomcode]" >&2; exit 2 ;;
esac
