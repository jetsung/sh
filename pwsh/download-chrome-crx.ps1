#============================================================
# File: download-chrome-crx.ps1
# Description:从 Chomne 扩展 ID 列表中下载最新的扩展保存至本地文件夹
# URL: https://fx4.cn/wdlcrx
# ORIGIN: https://gist.asfd.cn/jetsung/download-crx/raw/HEAD/windows.ps1
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.1
# CreatedAt: 2025-08-21
# UpdatedAt: 2025-08-21
#============================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$ListFile,          # 第 1 个位置参数：扩展 ID 列表文件
    [string]$Pkg = 'crx',               # 第 2 个位置参数：保存的文件格式，默认 crx
    [string]$Proxy = ''         # 第 3 个可选参数：代理地址  'http://127.0.0.1:1088'，如果是 SOCKS5，改成 socks5h://127.0.0.1:1080
)

Get-Content $ListFile | ForEach-Object {
    $id = $_.Trim()
    if (-not $id) { continue }

    $url = "https://clients2.google.com/service/update2/crx?response=redirect&prodversion=135.0&acceptformat=crx2,crx3&x=id%3D$id%26uc"
    $outFile = "$PWD\$id.$Pkg"

    Write-Host "下载: https://chromewebstore.google.com/detail/$id "
    try {
        if ($Proxy) {
            Invoke-WebRequest -Uri $url -Proxy $Proxy -OutFile $outFile
        } else {
            Invoke-WebRequest -Uri $url -OutFile $outFile
        }
        Write-Host "已保存：$outFile"
    } catch {
        Write-Warning "下载失败：$id （$($_.Exception.Message)）"
    }
}

# Invoke-WebRequest -Uri "https://fx4.cn/wdlcrx" -OutFile "download-crx.ps1"
# 本地： .\download-crx.ps1 E:\chromium.txt crx http://127.0.0.1:1088
# 网络： & ([scriptblock]::Create((irm https://fx4.cn/wdlcrx))) E:\chromium.txt crx http://127.0.0.1:1088
