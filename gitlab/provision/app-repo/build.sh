#!/bin/bash
# =====================================================================
# ダミービルドバッチ
#
# 本物のビルド処理の代わりに「ビルド成果物」と書いたテキストを出力する。
# 本番移行時は、この中身を実際のビルドコマンドに置き換える。
#
# 使い方: build.sh <プラットフォームのディレクトリ> <出力先ディレクトリ>
# =====================================================================
set -euo pipefail

PLATFORM_DIR="${1:?プラットフォームのディレクトリを指定してください}"
OUT_DIR="${2:?出力先ディレクトリを指定してください}"
APP_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$OUT_DIR"

APP_COMMIT="$(git -C "$APP_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")"
PLATFORM_VERSION="$(cat "$PLATFORM_DIR/version.txt" 2>/dev/null || echo "unknown")"

echo "ビルド開始: アプリ=${APP_COMMIT} プラットフォーム=${PLATFORM_VERSION}"
sleep 2  # ビルドにかかる時間のダミー

{
    echo "ビルド成果物"
    echo "----------------------------------------"
    echo "アプリコミット   : ${APP_COMMIT}"
    echo "プラットフォーム : ${PLATFORM_VERSION}"
    echo "ビルド日時       : $(date '+%Y-%m-%d %H:%M:%S')"
} > "$OUT_DIR/build_artifact.txt"

echo "ビルド完了: ${OUT_DIR}/build_artifact.txt"
