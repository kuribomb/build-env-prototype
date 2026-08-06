FROM jenkins/jenkins:lts-jdk17

# 社内プロキシ(SSLインスペクション)環境対応:
# リポジトリ直下の certs/ に置いたCA証明書(*.crt)を
# OSの証明書ストアと Java の truststore の両方に登録する
USER root
COPY --from=certs / /tmp/extra-certs/
RUN if ls /tmp/extra-certs/*.crt >/dev/null 2>&1; then \
      cp /tmp/extra-certs/*.crt /usr/local/share/ca-certificates/ && \
      update-ca-certificates && \
      for c in /tmp/extra-certs/*.crt; do \
        keytool -importcert -noprompt -cacerts -storepass changeit \
          -alias "extra-$(basename "$c" .crt)" -file "$c"; \
      done; \
    fi && rm -rf /tmp/extra-certs
USER jenkins

# プラグインはビルド時に焼き込む(plugins.txt で宣言的に管理)
# JAVA_PROXY_OPTS: プロキシ環境でのプラグイン取得用 (例: -Dhttps.proxyHost=... -Dhttps.proxyPort=...)
ARG JAVA_PROXY_OPTS=""
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN JAVA_TOOL_OPTIONS="${JAVA_PROXY_OPTS}" \
    jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
