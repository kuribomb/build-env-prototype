#!/usr/bin/env bash
# =====================================================================
# GitLab 初期データ投入スクリプト(setup.sh から呼ばれる)
#
#   1. root ユーザーのアクセストークン(PAT)を登録
#   2. app-repo / platform-repo プロジェクトを作成
#   3. ダミーの履歴(app: 複数コミット / platform: バージョンタグ)を push
#
# 冪等: 既に存在するものはスキップするため、何度実行してもよい
# =====================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

set -a
# shellcheck disable=SC1091
source "$ROOT_DIR/.env"
set +a

GITLAB_LOCAL="http://localhost:${GITLAB_PORT:-8929}"
API="$GITLAB_LOCAL/api/v4"
AUTH_HEADER="PRIVATE-TOKEN: ${GITLAB_PAT}"
PUSH_BASE="http://root:${GITLAB_PAT}@localhost:${GITLAB_PORT:-8929}/root"

log() { echo "[provision] $*"; }

git_config() {
    git config user.name "ビルド環境プロトタイプ"
    git config user.email "build-env-prototype@example.com"
}

# ---------- 1. アクセストークン登録 ----------
if curl -fsS -H "$AUTH_HEADER" "$API/user" >/dev/null 2>&1; then
    log "アクセストークンは登録済み"
else
    log "root のアクセストークンを登録します(1分ほどかかります)"
    docker compose -f "$ROOT_DIR/docker-compose.yml" exec -T gitlab gitlab-rails runner "
      user = User.find_by_username('root')
      token = user.personal_access_tokens.create!(
        scopes: ['api', 'read_repository', 'write_repository'],
        name: 'prototype-provision',
        expires_at: 364.days.from_now
      )
      token.set_token('${GITLAB_PAT}')
      token.save!
    "
    curl -fsS -H "$AUTH_HEADER" "$API/user" >/dev/null
    log "アクセストークンを登録しました"
fi

# ---------- 2. プロジェクト作成 ----------
# 戻り値 0: 新規作成した / 1: 既に存在していた
ensure_project() {
    local name="$1"
    if curl -fsS -H "$AUTH_HEADER" "$API/projects/root%2F${name}" >/dev/null 2>&1; then
        log "プロジェクト ${name} は作成済み"
        return 1
    fi
    curl -fsS -X POST -H "$AUTH_HEADER" "$API/projects" --data "name=${name}" >/dev/null
    log "プロジェクト ${name} を作成しました"
}

# ---------- 3. ダミー履歴の push ----------
provision_app_repo() {
    local work
    work="$(mktemp -d)"
    cp -r "$SCRIPT_DIR/app-repo/." "$work/"
    (
        cd "$work"
        git init -q -b main
        git_config
        chmod +x build.sh

        git add -A && git commit -qm "アプリ初期実装とビルドバッチを追加"

        echo '// 機能: ログイン処理' >> src/main.c
        git add -A && git commit -qm "ログイン機能を追加"

        echo '// 機能: データ同期処理' >> src/main.c
        git add -A && git commit -qm "データ同期機能を追加"

        printf '\n## 更新履歴\n\n- ログイン機能・データ同期機能を追加\n' >> README.md
        git add -A && git commit -qm "READMEに更新履歴を追記"

        git push -q "${PUSH_BASE}/app-repo.git" main
    )
    rm -rf "$work"
    log "app-repo にダミーのコミット履歴を push しました"
}

provision_platform_repo() {
    local work
    work="$(mktemp -d)"
    cp -r "$SCRIPT_DIR/platform-repo/." "$work/"
    (
        cd "$work"
        git init -q -b main
        git_config

        echo "1.0.0" > version.txt
        git add -A && git commit -qm "プラットフォーム v1.0.0"
        git tag -a v1.0.0 -m "安定版 v1.0.0"

        echo "1.1.0" > version.txt
        echo '// v1.1: 省電力APIを追加' >> lib/platform.h
        git add -A && git commit -qm "プラットフォーム v1.1.0: 省電力APIを追加"
        git tag -a v1.1.0 -m "機能追加版 v1.1.0"

        echo "2.0.0" > version.txt
        echo '// v2.0: 新世代SoC対応' >> lib/platform.h
        git add -A && git commit -qm "プラットフォーム v2.0.0: 新世代SoC対応"
        git tag -a v2.0.0 -m "メジャーアップデート v2.0.0"

        git push -q "${PUSH_BASE}/platform-repo.git" main --tags
    )
    rm -rf "$work"
    log "platform-repo にダミーのバージョンタグを push しました"
}

if ensure_project "app-repo"; then provision_app_repo; fi
if ensure_project "platform-repo"; then provision_platform_repo; fi

log "GitLab 初期データ投入 完了"
