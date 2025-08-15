## WPS

- **下载**
  ```bash
  curl -fsSL https://linux.wps.cn | grep '\.deb' | head -n 1 | awk -F '"' '{print $2}'
  ```
  > 地址已加密，无法直接下载。具体可查看该网页源代码。

- **版本号**
  ```bash
  curl -fsSL https://linux.wps.cn | sed -n '/banner_txt/p' | tail -n 1 | grep -oP '(?<=">)[0-9.]+(?=</)'
  ```
  