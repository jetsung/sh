# DNS 可用性测试脚本

一组用于批量测试公共 DNS 服务器连通性/可用性的 Shell 脚本，覆盖传统 DNS（53 端口）、DoH（DNS-over-HTTPS）与 DoT（DNS-over-TLS）三种方式。所有脚本均在能直连公网的机器上运行（不含代理设置），结果文件输出到当前目录，运行前清空重写。

## 脚本一览

| 脚本 | 测试对象 | 依赖 | 默认清单 | 结果文件 |
| --- | --- | --- | --- | --- |
| `test_dns.sh` | 传统 DNS 服务器（UDP 53，TCP 兜底） | `dig`（推荐）；缺失时回退 `python3` | `.file_dns` / `-6` 时 `.file_dns6` | `dns_ok.txt`、`dns_fail.txt`（IPv6 为 `dns6_ok.txt`、`dns6_fail.txt`） |
| `test_doh.sh` | DoH 端点（RFC 8484，GET + POST） | `curl`、`python3` | `.file_doh` | `doh_ok.txt`、`doh_fail.txt` |
| `test_dot.sh` | DoT 主机名（RFC 7858，853 端口） | `python3`（标准库 `ssl`） | `.file_dot` | `dot_ok.txt`、`dot_fail.txt` |

## 用法

### 传统 DNS（test_dns.sh）

```bash
bash test_dns.sh                       # IPv4，默认读取 ./.file_dns
bash test_dns.sh ./.file_other         # IPv4，指定其他清单
bash test_dns.sh -6                    # IPv6，默认读取 ./.file_dns6
bash test_dns.sh --ipv6 ./.file_dns6_other
```

- `-6` / `--ipv6`：切换 IPv6 模式（默认清单、结果文件、底层套接字均随之切换）。
- 测试域名由脚本顶部 `DOMAIN` 变量控制（默认 `example.com`；国内服务器建议同时测一个国内域名，如 `www.qq.com`）。
- 测试顺序：dig UDP → dig TCP → python3 socket（UDP）兜底。
- `dns_ok.txt` 与源清单格式一致（只保留测试通过的 IP，按清单原有顺序聚合），可直接复用为清单。

### DoH（test_doh.sh）

```bash
bash test_doh.sh                       # 默认读取 ./.file_doh（每行一个 DoH URL）
bash test_doh.sh ./.file_doh_other     # 指定其他清单文件
bash test_doh.sh https://doh.pub/dns-query   # 直接传入单个 DoH URL
```

- 同时以 GET（`?dns=<base64url>`）和 POST 两种方式请求；GET 不跟随重定向（301 仅作提示），POST 跟随重定向并保持 POST（兼容 CleanBrowsing 等旧端点 301 跳转）。
- 判定成功标准：POST 返回 200 且解析到 A 记录。
- 需要代理时：`export https_proxy=...` 后运行。

### DoT（test_dot.sh）

```bash
bash test_dot.sh                  # 默认读取 ./.file_dot（每行一个 DoT 主机名）
bash test_dot.sh ./.file_dot_other
bash test_dot.sh dot.pub          # 直接传入单个 DoT 主机名
```

- 未指定清单时使用内置 5 个主机：`dot.pub`、`dns.google`、`one.one.one.one`、`dns.quad9.net`、`dns.alidns.com`。
- 通过 TLS（853 端口）发送 DNS 查询并解析 A 记录。

## 清单格式

- `test_dns.sh`：每行「名称|地址1,地址2」，如 `阿里云 DNS|223.5.5.5,223.6.6.6`；仓库内示例见 [`dns_servers.txt`](./dns_servers.txt)。
- `test_doh.sh`：每行一个 DoH URL，如 `https://doh.pub/dns-query`。
- `test_dot.sh`：每行一个 DoT 主机名，如 `dot.pub`。
- 三者通用规则：`#` 开头为注释行，空行忽略。

## 结果文件

- `<前缀>_ok.txt`：测试通过的条目（`test_dns.sh` 的格式与源清单一致，可直接复用为清单；DoH/DoT 每行一个端点/主机）。
- `<前缀>_fail.txt`：不可用条目（DoH 附带 HTTP 状态码与解析详情；DoT 附带失败原因）。
- 终端回显上色：✅ 成功=绿，⚠️ 软失败（有响应但无 A 记录等）=黄，❌ 失败=红。
