# =====================================================================
# LAN公開の解除スクリプト(Windows側 / 管理者 PowerShell で実行)
# expose-lan.ps1 で設定したポート転送とファイアウォール許可を削除する
# =====================================================================
$ErrorActionPreference = "Stop"

$ports = @(8000, 8080, 8081, 8082, 8929)
$ruleName = "BuildEnvPrototype"

foreach ($p in $ports) {
    netsh interface portproxy delete v4tov4 listenport=$p listenaddress=0.0.0.0 2>$null | Out-Null
    Write-Host "ポート転送を削除: $p"
}

Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
Write-Host "ファイアウォールルールを削除: $ruleName"
