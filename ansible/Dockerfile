FROM docker:27-cli AS dockercli

FROM python:3.12-slim

# 社内プロキシ(SSLインスペクション)環境対応:
# リポジトリ直下の certs/ に置いたCA証明書(*.crt)を信頼させる
COPY --from=certs / /tmp/extra-certs/
RUN if ls /tmp/extra-certs/*.crt >/dev/null 2>&1; then \
      cp /tmp/extra-certs/*.crt /usr/local/share/ca-certificates/ && \
      update-ca-certificates; \
    fi && rm -rf /tmp/extra-certs
ENV PIP_CERT=/etc/ssl/certs/ca-certificates.crt \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

# ホストの Docker デーモンを操作するための docker CLI のみを取り込む
# (dockerd 自体はホスト側のものを /var/run/docker.sock 経由で使う)
COPY --from=dockercli /usr/local/bin/docker /usr/local/bin/docker

RUN apt-get update \
    && apt-get install -y --no-install-recommends openssh-client git curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir ansible-core

ENTRYPOINT ["ansible-playbook"]
CMD ["site.yml"]
