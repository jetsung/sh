# 编译安装库和软件

1. 编译库或软件   
2. 安装二进制软件


## 脚本说明

| **推荐** | **文件名** | **标题** | **描述** |
|:---|:---|:---|:---|
| | [**`acme-docker`**](acme-docker.sh) | acme docker 方式脚本 |
| | [**`aliyunpan`**](aliyunpan.sh)  |  安装 aliyunpan |
| | [**`croc`**](croc.sh)  |  安装 croc |
| | [**`frp`**](frp.sh)  |  安装 frp |
| | [**`gitlab-runner`**](gitlab-runner.sh)  |  安装 GitLab Runner |
| | [**`nginx`**](nginx.sh)  |  安装 Nginx |
| | [**`php-8`**](php-8.sh)  |  安装 PHP 8 |
| | [**`protoc`**](protoc.sh)  |  安装 protobuf |
| | [**`redis`**](redis.sh)  |  安装 Redis |
| | [**`ttyd`**](ttyd.sh)  |  安装 ttyd |

- [list.txt](list.txt)

```bash
rm -rf list.txt
for file in *.sh; do
    if [[ -f "$file" ]]; then
        title=$(grep -m1 '^# Description:' "$file" | cut -d':' -f2- | xargs)  # 提取标题
        if [[ -n "$title" ]]; then
            echo "$file  |  $title" >> list.txt
        else
            echo "$file" >> list.txt  # 处理无 description 的情况
        fi
    fi
done
```