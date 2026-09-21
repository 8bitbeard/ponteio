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

RUN mix local.hex --force \
    && mix local.rebar --force

WORKDIR /app

EXPOSE 4000

CMD ["mix", "phx.server"]
