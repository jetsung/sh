## PHP

- **下载** 
  ```bash
  curl -fsSL https://www.php.net | sed -n '/hero__version-link/p' | awk -F'[<>]' '{print "https://www.php.net/distributions/php-" $5 ".tar.gz"}' | head -n 1
  ```

- **版本号**
  ```bash
  curl -fsSL https://www.php.net | sed -n '/hero__version-link/p' | grep -oP '(?<=>)[0-9.]+(?=</a>)' | head -n 1 
  ```

  ```bash
  curl -fsSL https://www.php.net | sed -n '/hero__version-link/p' | awk -F'[<>]' '{print $5}' | head -n 1
  ```