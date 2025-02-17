# My Scripts

我的脚本文件

## 目录列表

```bash
├── conf     # 软件配置文件
├── init.d   # 软件启动文件
├── install  # 软件安装脚本
├── origin   # 脚本源
├── shell    # 自己编写的脚本
└── snippets # 自己编写的脚本片段 
```

## 安装脚本

安装前置依赖
```bash
sudo apt install -y jq
```

拉取源代码
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
- https://gitcode.com/jetsung/sh
- https://github.com/jetsung/sh
