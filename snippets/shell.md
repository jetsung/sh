# Shell

https://forum.idev.top/d/986

---

## 一、判断

### 判断是否为 URL 的函数
```sh
# 判断是否为 URL 的函数
is_url() {
    local url="$1"
    # 正则表达式匹配 URL
    if [[ "$url" =~ ^https?://[^[:space:]]+ ]]; then
        return 0  # 是 URL
    else
        return 1  # 不是 URL
    fi
}
```

---
### 判断是否
```sh
is_command() {
    command -v "$1" >/dev/null 2>&1
}
```

---
### 判断是否为中国网络
```sh
is_in_china() {
    if [ "$(curl -s -m 3 -o /dev/null -w "%{http_code}" https://www.google.com)" != "200" ]; then
        return 0 # 中国网络
    fi
    return 1 # 非中国网络
}
```

---
### 判断文件是否为 JSON
```sh
is_json() {
    if file --mime-type "$1" | grep -q 'application/json'; then
        if jq empty "$1" >/dev/null 2>&1; then
            return 0
        else
            return 1
        fi
    else
        return 2
    fi
}
```

---

## 二、获取

### URL 转义函数
```sh
get_escape() {
  local input="$1"
  local escaped=""
  
  # 遍历输入字符串中的每一个字符
  for (( i=0; i<${#input}; i++ )); do
    char="${input:$i:1}"
    
    # 检查字符是否需要转义
    case "$char" in
      # 保留字符无需转义 (RFC 3986)
      [A-Za-z0-9-_.~])
        escaped+="$char"
        ;;
      # 其他字符进行转义
      *)
        # 将字符转换为 ASCII 十六进制形式
        hex=$(printf "%02X" "'$char")
        escaped+="%$hex"
        ;;
    esac
  done
  
  echo "$escaped"
}
```

---

## 常用命令

### 查看

#### 查看当前子目录名称
```sh
# ls
ls -l | grep '^d' | awk '{print $9}' 

# find
find . -maxdepth 1 -name ".git" -prune -o -type d -printf "%f\n"

# tree
tree -d --prune -I ".git" -L 1 | awk '{print $2}' | tail -n +2 | head -n -2
```
