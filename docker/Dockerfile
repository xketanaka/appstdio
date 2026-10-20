FROM ruby:4.0.2

RUN apt-get update
RUN apt-get install -y locales
RUN localedef -f UTF-8 -i ja_JP /usr/lib/locale/ja_JP.UTF-8
ENV LC_ALL=ja_JP.UTF-8
RUN ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime

RUN apt-get update && apt-get install -y \
		bzip2 \
		ca-certificates \
		libffi-dev \
		libgdbm-dev \
		libssl-dev \
		libreadline-dev \
		libyaml-dev \
		procps \
		zlib1g-dev

## デフォルトで入っていないパッケージ
RUN apt-get update && apt-get install -y sudo poppler-utils build-essential git vim curl
## psql、pg_dump コマンドを使用するため、PGDG から postgresql-client をインストール
RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/keyrings/pgdg.gpg
RUN echo \
  "deb [signed-by=/etc/apt/keyrings/pgdg.gpg] https://apt.postgresql.org/pub/repos/apt \
  $(. /etc/os-release && echo "$VERSION_CODENAME")-pgdg main" | tee /etc/apt/sources.list.d/pgdg.list > /dev/null
RUN apt-get update && apt-get install -y libpq-dev postgresql-client-18
## フロントエンドのビルド（Vite）用の Node。Debian の nodejs には npm が付かず版も古いので、公式イメージから持ってくる
COPY --from=node:24-trixie-slim /usr/local/bin/node /usr/local/bin/
COPY --from=node:24-trixie-slim /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && \
    ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

## system test 用のブラウザ。arm64 では Selenium が Chrome を取ってこられないので、OS のパッケージを使う
RUN apt-get update && apt-get install -y chromium chromium-driver fonts-noto-cjk

## dockerコマンドインストール
RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
RUN echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
RUN apt update && apt install -y docker-ce-cli

COPY files/entrypoint.sh /usr/bin/
RUN chmod +x /usr/bin/entrypoint.sh
ENTRYPOINT ["entrypoint.sh"]

CMD ["irb"]