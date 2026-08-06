#!/bin/bash
# =====================================================================
# Jenkins Agent コンテナのエントリポイント
#   1. NAS相当のボリューム(/nas)を jenkins ユーザーが書けるようにする
#   2. 環境変数で渡された公開鍵を jenkins ユーザーに登録する
#   3. sshd をフォアグラウンドで起動する
# =====================================================================
set -e

mkdir -p /nas
chown jenkins:jenkins /nas

if [ -z "${JENKINS_AGENT_SSH_PUBKEY:-}" ]; then
    echo "ERROR: JENKINS_AGENT_SSH_PUBKEY が設定されていません" >&2
    exit 1
fi
mkdir -p /home/jenkins/.ssh
echo "${JENKINS_AGENT_SSH_PUBKEY}" > /home/jenkins/.ssh/authorized_keys
chown -R jenkins:jenkins /home/jenkins/.ssh
chmod 700 /home/jenkins/.ssh
chmod 600 /home/jenkins/.ssh/authorized_keys

exec /usr/sbin/sshd -D -e
