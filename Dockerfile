## Dockerfile de desenvolvimento do Ponteio.
##
## Roda `mix phx.server` com hot code reload dentro do container. O código
## da aplicação é montado como volume pelo docker-compose.yml (não é
## copiado na imagem), então este Dockerfile só instala o toolchain
## Elixir/Erlang/Node e as dependências de sistema necessárias para
## compilar a aplicação e seus assets.
##
## Não é (ainda) um Dockerfile de produção multi-stage — isso é tratado
## em issue própria quando o deploy entrar em pauta.

ARG ELIXIR_VERSION=1.18.3
ARG OTP_VERSION=27

FROM elixir:${ELIXIR_VERSION}-otp-${OTP_VERSION}-slim

RUN apt-get update -qq \
    && apt-get install -y --no-install-recommends \
      build-essential \
      git \
      ca-certificates \
      inotify-tools \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && update-ca-certificates

## Usuário não-root: evita que arquivos gerados dentro do container (deps,
## _build, migrations, snapshots do Ash etc.) fiquem com dono `root` no host
## através do bind mount `.:/app` do docker-compose.yml. UID/GID default
## (1000) casam com o usuário padrão da maioria das distros Linux; se o seu
## host usar outro UID/GID, sobrescreva via `--build-arg UID=$(id -u) --build-arg GID=$(id -g)`.
ARG UID=1000
ARG GID=1000

RUN groupadd -g "${GID}" app \
    && useradd -m -u "${UID}" -g "${GID}" -s /bin/bash app \
    && mkdir -p /app/deps /app/_build /app/assets/node_modules \
    && chown -R app:app /app

USER app

RUN mix local.hex --force \
    && mix local.rebar --force

WORKDIR /app

EXPOSE 4000

CMD ["mix", "phx.server"]
