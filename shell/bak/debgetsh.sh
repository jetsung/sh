#!/bin/sh

# ORIGIN: https://framagit.org/-/snippets/7181/raw/main/get.sh

APT_URL="https://apt.asfd.cn"
APT_GPG="idev.gpg"
GPG_PATH="/etc/apt/trusted.gpg.d/$APT_GPG"
APT_PATH="/etc/apt/sources.list.d/idev.list"

if [ "$(id -u)" -eq 0 ]; then
  curl -fsSL "$APT_URL/$APT_GPG" | gpg --dearmor | tee "$GPG_PATH" > /dev/null
  echo "deb [arch=$(dpkg --print-architecture)] $APT_URL stable main" | tee "$APT_PATH" > /dev/null
  apt update -y
else
  curl -fsSL "$APT_URL/$APT_GPG" | gpg --dearmor | sudo tee "$GPG_PATH" > /dev/null
  echo "deb [arch=$(dpkg --print-architecture)] $APT_URL stable main" | sudo tee "$APT_PATH" > /dev/null
  sudo apt update -y
fi
