## GitHub

- **下载**
  ```bash
  curl -s "https://api.github.com/repos/msojocs/wechat-web-devtools-linux/releases/latest" | grep browser_download_url | awk -F '"' '{print $4}' | grep -E 'amd|deb' | head -n 1
  ```

- **版本号**
  ```bash
  curl -s "https://api.github.com/repos/msojocs/wechat-web-devtools-linux/releases/latest" | grep tag_name | awk -F '"' '{print $4}' | head -n 1
  ```

### 软件列表
```bash
msojocs/wechat-web-devtools-linux

# 获取下载链接
echo 'msojocs/wechat-web-devtools-linux' | xargs -I {} curl -s "https://api.github.com/repos/{}/releases/latest" | grep browser_download_url | awk -F '"' '{print $4}' | grep -E 'amd|deb' | head -n 1
```

### 批量提取链接
- 文件 `repo.list`。注意，最后必须空一行。
```bash
msojocs/wechat-web-devtools-linux
lyswhut/lx-music-desktop
BurntSushi/ripgrep 
localsend/localsend

```

- 执行文件。
```bash
#!/usr/bin/env bash

set -euo pipefail

while IFS= read -r repo; do
    echo "$repo" | xargs -I {} curl -s "https://api.github.com/repos/{}/releases/latest" | grep browser_download_url | awk -F '"' '{print $4}' | grep -E 'amd|deb' | head -n 1
done < repo.list  
```

### 配合 `debfetch`
```bash
#!/usr/bin/env bash

set -euo pipefail

APT_ROOT_PATH="${APTPATH:-/root/downloads}"
DEB_POOL_PATH="${DEBPATH:-$APT_ROOT_PATH/pool/main}"

while IFS= read -r repo; do
  soft_url=$(echo "$repo" | tr -d ' ' | xargs -I {} curl -s "https://api.github.com/repos/{}/releases/latest" | grep browser_download_url | awk -F '"' '{print $4}' | grep -E '(x86[-_]?64|amd64).*\.deb$' | head -n 1)
  soft_name=$(basename "$soft_url")

  deb_file_path="${DEB_POOL_PATH}/${soft_name}"
  if [ ! -f "${deb_file_path}" ]; then
      debfetch -s -u "$soft_url"
  else
      echo "File already exists: ${deb_file_path}"
  fi
  echo
done < repo.list

echo

debfetch
```