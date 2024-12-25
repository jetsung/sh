## Sublime Text

- **下载**   
  ```bash
  curl -fsSL https://www.sublimetext.com/download_thanks\?target\=x64-deb | grep amd64.deb | cut -d'"' -f2 | head -n 1
  ```
  
- **版本号**
  ```bash
  curl -fsSL https://www.sublimetext.com/download_thanks\?target\=x64-deb | grep amd64.deb | cut -d'"' -f2 | head -n 1 | grep -oP '(?<=-)[0-9]+(?=_amd64)'
  ```