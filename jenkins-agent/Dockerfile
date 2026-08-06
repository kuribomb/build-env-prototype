# =====================================================================
# Jenkins Agent(Linuxビルドサーバー役)
#
# 本番想定の「素のLinuxサーバー + sshd + JDK + git」をそのまま再現する。
# Jenkins コントローラから SSH で接続され、ビルドが実行される。
# 本番展開時はこの Dockerfile の内容が、実サーバーのセットアップ手順
# (Ansible等)に対応する。
# =====================================================================
FROM ubuntu:24.04

# ビルドサーバーに必要なもの:
#   openssh-server          : Jenkins からの SSH 接続の受け口
#   openjdk-17-jre-headless : Jenkins Agent(remoting)の実行に必要
#   git                     : リポジトリ取得
#   curl                    : Teams 通知の送信
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        openssh-server openjdk-17-jre-headless git curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# 社内プロキシ(SSLインスペクション)環境対応:
# リポジトリ直下の certs/ に置いたCA証明書(*.crt)を信頼させる
COPY --from=certs / /tmp/extra-certs/
RUN if ls /tmp/extra-certs/*.crt >/dev/null 2>&1; then \
      cp /tmp/extra-certs/*.crt /usr/local/share/ca-certificates/ && \
      update-ca-certificates; \
    fi && rm -rf /tmp/extra-certs

# Jenkins が SSH ログインするユーザーと作業ディレクトリ
RUN useradd --create-home --shell /bin/bash jenkins && \
    mkdir -p /home/jenkins/agent && \
    chown -R jenkins:jenkins /home/jenkins && \
    mkdir -p /run/sshd

COPY entrypoint.sh /usr/local/bin/agent-entrypoint.sh
RUN chmod +x /usr/local/bin/agent-entrypoint.sh

EXPOSE 22
ENTRYPOINT ["/usr/local/bin/agent-entrypoint.sh"]
