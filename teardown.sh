#!/usr/bin/env bash
# =====================================================================
# ビルド環境プロトタイプ 削除スクリプト
#
#   ./teardown.sh          コンテナと全データ(ボリューム)を削除
#   ./teardown.sh --keep   コンテナのみ停止・削除(データは残す)
#
# --keep なしで削除した後に ./setup.sh を実行すると、初期状態から
# 再構築される(再現性の確認にも使える)
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")"

if [ "${1:-}" = "--keep" ]; then
    docker compose down --remove-orphans
    echo "[teardown] コンテナを停止・削除しました(データは保持)"
else
    read -r -p "全コンテナとデータ(GitLabリポジトリ・Jenkins履歴)を削除します。よろしいですか? [y/N] " ans
    case "$ans" in
        [yY]*)
            docker compose down -v --remove-orphans
            echo "[teardown] コンテナと全データを削除しました"
            echo "[teardown] NAS(nas-data/ ホストディレクトリ)は本番のNASと同様に削除されません。手動で削除する場合は 'rm -rf nas-data/*' を実行してください"
            ;;
        *)
            echo "[teardown] 中止しました"
            ;;
    esac
fi
