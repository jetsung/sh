## Go

- **下载**
  ```bash
  curl -fsSL https://golang.google.cn/dl/ |  sed -n '/download downloadBox/p' | head -n 4 | awk -F'"' '{print "https://golang.google.cn" $4}' | head -n 4 | tail -n 1 
  ```

- **版本号**
  ```bash
  curl -fsSL https://golang.google.cn/dl/ |  sed -n '/download downloadBox/p' | head -n 1 | grep -oP '(?<=go)[0-9.]+(?=.win)'
  ```

  ```bash
  curl -fsSL https://golang.google.cn/dl/ |  sed -n '/toggle/p' | cut -d '"' -f 4 | grep go | grep -Ev 'rc|beta' | head -n 1 | grep -oP '(?<=go)[0-9.]+'
  ```
