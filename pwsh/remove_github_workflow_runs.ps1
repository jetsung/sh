#============================================================
# File: Remove-GitHubWorkflowRuns.ps1
# Description: 批量删除 GitHub Action Workflows 流水线
# URL: https://s.fx4.cn/
# ORIGIN: https://gist.asfd.cn/jetsung/githubci/raw/HEAD/remove_github_workflow_runs.ps1
# Author: Jetsung Chan <i@jetsung.com>
# Ported to PowerShell by: Jetsung Chan
# Version: 0.1.0
# CreatedAt: 2025-08-27
# UpdatedAt: 2025-08-27
# Requires: PowerShell 7+, GitHub CLI (gh), jq (optional, but used here)
#============================================================

# 等效于 set -e: 遇到错误（非0退出码或异常）立即终止脚本
# $ErrorActionPreference = "Stop"

# 等效于 set -u: 严格模式，禁止使用未初始化的变量
# Set-StrictMode -Version Latest

# 等效于 set -x: 跟踪命令执行（显示执行的命令）
# Set-PSDebug -Trace 1

# 或者（退出程序）
# Set-PSDebug -Off

param(
    [Parameter(Mandatory = $true)]
    [string]$OrgName,

    [Parameter(Mandatory = $true)]
    [string]$RepoName
)

# 启用严格模式
$ErrorActionPreference = 'Stop'
if ($env:DEBUG) { $PSNativeCommandUseErrorActionPreference = $true }

$Repo = "$OrgName/$RepoName"
$Url = "repos/$Repo/actions/runs"

$TotalDeleted = 0

function Delete-RunId {
    param([string]$Id)

    Write-Host "Deleting URL: $Url/$Id"
    $Result = $null

    try {
        # 使用 gh api 删除指定的 workflow run
        gh api -X DELETE "$Url/$Id" --silent | Out-Null
        $Result = "✅ Deleted '$Id'"
        $script:TotalDeleted++
    }
    catch {
        $Result = "❌ Failed '$Id'"
        Write-Host $Result
        Write-Host "An error occurred while deleting ID '$Id'. Press Enter to exit."
        Write-Host "Total IDs deleted: $script:TotalDeleted"
        $null = Read-Host
        exit 1
    }

    Write-Host $Result
}

# 设置 UTF-8 输出编码（关键！）
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 可选环境变量
$env:GH_NO_COLOR = "1"
$env:NO_COLOR = "1"

while ($true) {
	try {
		# 使用 --jq '.' 获取纯净 JSON，并确保 UTF-8 输出
		$JsonOutput = gh api "$Url" --jq '.' 2>$null

		# 清理 ANSI 颜色码
		$JsonOutput = $JsonOutput -replace "\x1B\[[0-9;]*[a-zA-Z]", ""
		$JsonOutput = $JsonOutput.Trim()

		if ([string]::IsNullOrWhiteSpace($JsonOutput)) {
			Write-Host "空响应。按回车退出。"
			$null = Read-Host
			exit 0
		}

		# 现在可以正确解析含中文的 JSON
		$Response = $JsonOutput | ConvertFrom-Json

	} catch {
		Write-Error "JSON 解析失败。原始内容：`n$JsonOutput"
		exit 1
	}

    $Runs = $Response.workflow_runs
    $TotalIds = $Runs.Count

    if ($TotalIds -eq 0) {
        Write-Host "No more IDs to delete. Press Enter to exit."
        Write-Host "Total IDs deleted: $TotalDeleted"
        $null = Read-Host
        break
    }

    foreach ($Run in $Runs) {
        $Id = $Run.id.ToString()  # 确保是字符串，并去除可能的换行符等
        Delete-RunId -Id $Id
    }

    # 可选：避免 API 限流，暂停 2 秒
    # Start-Sleep -Seconds 2
}