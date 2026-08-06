# =====================================================================
# LAN公開スクリプト(Windows側 / 管理者 PowerShell で実行)
#
# WSL2 は NAT 内にあるため、そのままでは他のPCからアクセスできない。
# このスクリプトは Windows のポートを WSL2 へ転送(portproxy)し、
# ファイアウォールで受信を許可する。
#
# 実行方法(管理者 PowerShell):
#   Set-ExecutionPolicy -Scope Process Bypass -Force
#   .\expose-lan.ps1
#
# 元に戻すには remove-lan.ps1 を実行する。
# =====================================================================
$ErrorActionPreference = "Stop"

# プロトタイプが使用するポート(.env のポートを変えた場合はここも合わせる)
$ports = @(8000, 8080, 8081, 8082, 8929)
$ruleName = "BuildEnvPrototype"

# WSL2 の現在の IP を取得(WSL2 再起動で変わるため、都度実行し直す)
$wslIp = (wsl hostname -I).Trim().Split(" ")[0]
if (-not $wslIp) {
    Write-Error "WSL2 の IP を取得できませんでした。WSL2 が起動しているか確認してください。"
    exit 1
}
Write-Host "WSL2 IP: $wslIp"

# ポート転送の設定(既存設定は入れ替え)
foreach ($p in $ports) {
    netsh interface portproxy delete v4tov4 listenport=$p listenaddress=0.0.0.0 2>$null | Out-Null
    netsh interface portproxy add v4tov4 listenport=$p listenaddress=0.0.0.0 `
        connectport=$p connectaddress=$wslIp | Out-Null
    Write-Host "ポート転送: 0.0.0.0:$p -> ${wslIp}:$p"
}

# ファイアウォールの受信許可
Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol TCP `
    -LocalPort $ports -Action Allow | Out-Null
Write-Host "ファイアウォール受信許可: $ruleName ($($ports -join ', '))"

# メンバーへ案内する IP(このPCの LAN IP)を表示
Write-Host ""
Write-Host "== このPCの LAN IP(メンバーにはこの IP で案内してください)=="
Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object {
        $_.IPAddress -notlike "127.*" -and
        $_.IPAddress -notlike "169.254.*" -and
        $_.InterfaceAlias -notlike "*WSL*" -and
        $_.InterfaceAlias -notlike "*Loopback*"
    } |
    Select-Object IPAddress, InterfaceAlias | Format-Table

Write-Host "次に WSL2 側で .env の HOST_ADDR を上記 IP に変更し、./setup.sh を再実行してください。"
