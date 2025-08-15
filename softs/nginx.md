## nginx

- **下载** 
  ```bash
  curl -fsSL https://nginx.org/en/download.html | grep -oP '<table[^>]*>\K.*?(?=</table>)' | head -n 2 | awk -F'"' '{print "https://nginx.org" $8}' | tail -n 1
  ```

- **版本号** 
  ```bash
  curl -fsSL https://nginx.org/en/download.html | grep -oP '<table[^>]*>\K.*?(?=</table>)' | head -n 2 | grep -oP '(?<=nginx-)\d+\.\d+\.\d+' | tail -n 1
  ``` 

  ```bash
  curl -fsSL https://nginx.org/en/download.html | grep -oP '<table[^>]*>\K.*?(?=</table>)' | head -n 2 | awk -F'"' '{print "https://nginx.org" $8}' | grep -oP '(?<=nginx-)[0-9.]+(?=.tar)' | tail -n 1
  ```