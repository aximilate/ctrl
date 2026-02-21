param(
    [string]$HostName = "176.32.37.18",
    [string]$HostUser = "root"
)

$ErrorActionPreference = "Stop"

function Assert-LastExitCode {
    param([string]$Step)
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed at step: $Step (exit code: $LASTEXITCODE)"
    }
}

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

Write-Host "1/6 Build Flutter Web"
flutter build web --release --dart-define=CTRLCHAT_API_URL=https://web.ctrlchat.ru/api
Assert-LastExitCode "flutter build web"

Write-Host "2/6 Prepare bundle"
$tmpDir = Join-Path $env:TEMP "ctrlchat_deploy_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -ItemType Directory -Path $tmpDir | Out-Null
Copy-Item -Recurse -Force build\web (Join-Path $tmpDir "web")
Copy-Item -Recurse -Force server (Join-Path $tmpDir "server")
Remove-Item -Recurse -Force (Join-Path $tmpDir "server\\node_modules") -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force (Join-Path $tmpDir "server\\data") -ErrorAction SilentlyContinue
Copy-Item -Force infra\ctrlchat-api.service (Join-Path $tmpDir "ctrlchat-api.service")
Copy-Item -Force infra\nginx\ctrlchat.conf (Join-Path $tmpDir "ctrlchat.conf")

$archive = Join-Path $env:TEMP "ctrlchat_deploy.tar.gz"
if (Test-Path $archive) { Remove-Item $archive -Force }
tar -czf $archive -C $tmpDir .
Assert-LastExitCode "tar bundle"

$target = "$HostUser@$HostName"

Write-Host "3/6 Upload bundle"
scp $archive "${target}:/root/ctrlchat_deploy.tar.gz"
Assert-LastExitCode "scp bundle"

Write-Host "4/6 Install/update on VPS"
$remoteScript = @"
set -e
mkdir -p /opt/ctrlchat
mkdir -p /var/www/ctrlchat
tar -xzf /root/ctrlchat_deploy.tar.gz -C /opt/ctrlchat
rm -f /root/ctrlchat_deploy.tar.gz

cp -r /opt/ctrlchat/web/* /var/www/ctrlchat/
cd /opt/ctrlchat/server
npm ci --omit=dev

if [ ! -f /opt/ctrlchat/server/.env ]; then
  cp /opt/ctrlchat/server/.env.example /opt/ctrlchat/server/.env
fi

cp /opt/ctrlchat/ctrlchat-api.service /etc/systemd/system/ctrlchat-api.service
cp /opt/ctrlchat/ctrlchat.conf /etc/nginx/sites-available/ctrlchat.conf
ln -sf /etc/nginx/sites-available/ctrlchat.conf /etc/nginx/sites-enabled/ctrlchat.conf

systemctl daemon-reload
systemctl enable ctrlchat-api
systemctl restart ctrlchat-api
nginx -t
systemctl restart nginx
"@

ssh $target $remoteScript
Assert-LastExitCode "remote install script"

Write-Host "5/6 Health check"
ssh $target "curl -sf http://127.0.0.1:8080/api/health"
Assert-LastExitCode "health check"

Write-Host "6/6 Done"
Write-Host "If first deploy: edit /opt/ctrlchat/server/.env and restart service:"
Write-Host "ssh $target 'nano /opt/ctrlchat/server/.env && systemctl restart ctrlchat-api'"
