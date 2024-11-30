# My Scripts

我的脚本文件

## 目录列表

```bash
├── conf    # 软件配置文件
├── init.d  # 软件启动文件
├── install # 软件安装脚本
├── origin  # 脚本源
└── shell   # Shell 脚本
```

## 安装脚本
1. 安装前置脚本
```bash
sudo apt install -y jq
```

```bash
git clone https://framagit.org/jetsung/sh.git
cd sh/install
```

**1. nginx**
```bash
bash nginx.sh
```

**2. protoc**
```bash
bash protoc.sh

# 或者
curl -s https://framagit.org/jetsung/sh/-/raw/main/install/protoc.sh | bash
```

## 仓库镜像

- https://git.jetsung.com/jetsung/sh
- https://framagit.org/jetsung/sh
- https://codeup.aliyun.com/jetsung/sh
