#!/usr/bin/env bash
# =====================================================================
# ビルド環境プロトタイプ 一括構築スクリプト
#
#   ./setup.sh            構築 + スモークテスト(初回は .env と SSH鍵を自動生成)
#   ./setup.sh --no-test  スモークテストを飛ばして構築のみ
#
# 冪等: 2回目以降の実行では既存の設定・データを維持したまま更新する
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")"

SKIP_TEST=0
[ "${1:-}" = "--no-test" ] && SKIP_TEST=1

log()  { echo -e "\e[1;34m[setup]\e[0m $*"; }
warn() { echo -e "\e[1;33m[setup]\e[0m $*"; }
die()  { echo -e "\e[1;31m[setup]\e[0m $*" >&2; exit 1; }

# ---------------------------------------------------------------
# 0. 前提チェック
# ---------------------------------------------------------------
command -v docker >/dev/null 2>&1 \
    || die "docker が見つかりません。README の『Docker Engine のインストール』を参照してください"
docker compose version >/dev/null 2>&1 \
    || die "docker compose (v2) が見つかりません。docker-compose-plugin をインストールしてください"
docker info >/dev/null 2>&1 \
    || die "Docker デーモンに接続できません(sudo が必要か、'sudo service docker start' を実行してください)"
command -v git >/dev/null 2>&1 || die "git が見つかりません"
command -v curl >/dev/null 2>&1 || die "curl が見つかりません"
command -v ssh-keygen >/dev/null 2>&1 || die "ssh-keygen が見つかりません"

MEM_KB=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
if [ "$MEM_KB" -lt $((8 * 1024 * 1024)) ]; then
    warn "メモリが 8GB 未満です。GitLab CE は約4GBのメモリを使用するため、動作が不安定になる可能性があります"
    warn "(WSL2 のメモリ上限は %UserProfile%\\.wslconfig で変更できます。README 参照)"
fi

# ---------------------------------------------------------------
# 1. .env と SSH鍵の生成(初回のみ)
# ---------------------------------------------------------------
gen_secret() { tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c "$1"; }

if [ ! -f .env ]; then
    log ".env を生成します(パスワード類は自動生成)"
    cp .env.example .env
    sed -i "s/^GITLAB_ROOT_PASSWORD=CHANGEME/GITLAB_ROOT_PASSWORD=$(gen_secret 20)/" .env
    sed -i "s/^GITLAB_PAT=CHANGEME/GITLAB_PAT=$(gen_secret 30)/" .env
    sed -i "s/^JENKINS_ADMIN_PASSWORD=CHANGEME/JENKINS_ADMIN_PASSWORD=$(gen_secret 20)/" .env
fi

if [ ! -f secrets/agent_ssh_key ]; then
    log "Jenkins Agent 接続用の SSH 鍵ペアを生成します"
    mkdir -p secrets
    ssh-keygen -q -t ed25519 -N '' -C 'jenkins-agent' -f secrets/agent_ssh_key
fi

# 公開鍵を .env に反映(jenkins-agent コンテナへ環境変数で渡すため)
AGENT_PUB="$(cat secrets/agent_ssh_key.pub)"
sed -i "s|^AGENT_SSH_PUBKEY=.*|AGENT_SSH_PUBKEY=\"${AGENT_PUB}\"|" .env

set -a
# shellcheck disable=SC1091
source ./.env
set +a

# NAS相当のホストディレクトリ(bind mount先)を用意しておく
mkdir -p "${NAS_HOST_PATH:-./nas-data}"

# ---------------------------------------------------------------
# 2. コンテナのビルドと起動
# ---------------------------------------------------------------
log "コンテナをビルド・起動します"
docker compose up -d --build

# ---------------------------------------------------------------
# 3. GitLab の起動待ちと初期データ投入
# ---------------------------------------------------------------
wait_healthy() {
    local name="$1" timeout="$2" elapsed=0
    while true; do
        local status
        status="$(docker inspect -f '{{.State.Health.Status}}' "$name" 2>/dev/null || echo unknown)"
        [ "$status" = "healthy" ] && return 0
        [ "$elapsed" -ge "$timeout" ] \
            && die "$name が ${timeout}秒 以内に起動しませんでした ('docker compose logs $name' で確認してください)"
        sleep 5
        elapsed=$((elapsed + 5))
    done
}

log "GitLab の起動を待ちます(初回は3〜5分かかります)"
wait_healthy gitlab 600
log "GitLab が起動しました"

./gitlab/provision/provision.sh

# ---------------------------------------------------------------
# 4. Jenkins の起動待ち(ジョブ定義と Agent 接続の確認)
# ---------------------------------------------------------------
log "Jenkins の起動を待ちます"
wait_healthy jenkins 300

JENKINS_LOCAL="http://localhost:${JENKINS_PORT:-8080}"
elapsed=0
until curl -fsS -u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}" \
        "${JENKINS_LOCAL}/job/platform-build/api/json" >/dev/null 2>&1; do
    [ "$elapsed" -ge 120 ] && die "Jenkins にジョブ platform-build が作成されていません"
    sleep 5; elapsed=$((elapsed + 5))
done
log "Jenkins のジョブ定義を確認しました"

elapsed=0
until curl -fsS -u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}" \
        "${JENKINS_LOCAL}/computer/linux-build-01/api/json" 2>/dev/null \
        | grep -q '"offline":false'; do
    [ "$elapsed" -ge 180 ] && die "Jenkins Agent (linux-build-01) がオンラインになりません"
    sleep 5; elapsed=$((elapsed + 5))
done
log "Jenkins Agent の接続を確認しました"

# ---------------------------------------------------------------
# 5. スモークテスト(ポータル経由で1ビルド実行し、全経路を確認)
# ---------------------------------------------------------------
if [ "$SKIP_TEST" -eq 0 ]; then
    log "スモークテスト: ポータル経由でビルドを1件実行します"

    PORTAL_LOCAL="http://localhost:${PORTAL_PORT:-8000}"
    elapsed=0
    until curl -fsS "${PORTAL_LOCAL}/healthz" >/dev/null 2>&1; do
        [ "$elapsed" -ge 120 ] && die "ポータルが起動しません"
        sleep 3; elapsed=$((elapsed + 3))
    done

    TEAMS_LOCAL="http://localhost:${TEAMS_PORT:-8082}"
    BEFORE_COUNT="$(curl -fsS "${TEAMS_LOCAL}/api/notifications" | grep -o 'received_at' | wc -l || echo 0)"

    curl -fsS -X POST -H "Content-Type: application/json" \
        -d '{"app_commit": "main", "platform_version": "v1.1.0"}' \
        "${PORTAL_LOCAL}/api/build" >/dev/null \
        || die "ポータルからのビルド発火に失敗しました"

    log "ビルドの完了と Teams 通知を待ちます"
    elapsed=0
    until [ "$(curl -fsS "${TEAMS_LOCAL}/api/notifications" | grep -o 'received_at' | wc -l)" -gt "$BEFORE_COUNT" ]; do
        [ "$elapsed" -ge 300 ] \
            && die "Teams 通知が届きません ('docker compose logs jenkins' と Jenkins のビルドログを確認してください)"
        sleep 5; elapsed=$((elapsed + 5))
    done

    curl -fsS "http://localhost:${NAS_PORT:-8081}/builds/" | grep -q 'platform-build' \
        || die "NAS に成果物が見つかりません"

    log "スモークテスト成功: ビルド → NAS保管 → Teams通知 の全経路を確認しました"
fi

# ---------------------------------------------------------------
# 6. アクセス情報の表示
# ---------------------------------------------------------------
cat <<EOF

=====================================================================
 構築完了! アクセスURL (HOST_ADDR=${HOST_ADDR})
---------------------------------------------------------------------
 ビルド依頼ポータル : http://${HOST_ADDR}:${PORTAL_PORT:-8000}/
 Jenkins            : http://${HOST_ADDR}:${JENKINS_PORT:-8080}/
                      (ユーザー: ${JENKINS_ADMIN_USER} / パスワード: .env の JENKINS_ADMIN_PASSWORD)
 GitLab             : http://${HOST_ADDR}:${GITLAB_PORT:-8929}/
                      (ユーザー: root / パスワード: .env の GITLAB_ROOT_PASSWORD)
 NAS(成果物)        : http://${HOST_ADDR}:${NAS_PORT:-8081}/
 Teams通知モック    : http://${HOST_ADDR}:${TEAMS_PORT:-8082}/
---------------------------------------------------------------------
 メンバーのPCからアクセスさせる場合:
   1. .env の HOST_ADDR を Windows の LAN IP に変更し ./setup.sh を再実行
   2. Windows 側で管理者 PowerShell から windows/expose-lan.ps1 を実行
=====================================================================
EOF
