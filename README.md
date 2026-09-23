# Ponteio

Plataforma web para aprendizado de músicas no violão via tablaturas, com sugestão automática de acordes de referência para cada trecho da música. Veja `docs/PRD-plataforma-tablaturas.md` e `docs/SDD-plataforma-tablaturas.md` para o produto e o design técnico completos.

Stack: Elixir + Phoenix LiveView + Ash Framework (AshPostgres) sobre PostgreSQL.

## Subindo o ambiente com Docker Compose

Pré-requisito: apenas Docker e Docker Compose — não é necessário instalar Elixir/Erlang na máquina.

```bash
cp .env.example .env
docker compose up
```

Isso sobe dois serviços:

* `db` — PostgreSQL 16, com dados persistidos no volume `ponteio_pgdata`.
* `app` — a aplicação Phoenix, que ao subir automaticamente roda `mix deps.get`, `mix ecto.create`, `mix ecto.migrate` e então `mix phx.server`.

Quando o log mostrar `Running PonteioWeb.Endpoint with Bandit ... at 0.0.0.0:4000`, a aplicação está acessível em [http://localhost:4000](http://localhost:4000).

Para rodar em background: `docker compose up -d`. Para acompanhar os logs: `docker compose logs -f app`. Para parar: `docker compose down` (adicione `-v` para também apagar o volume de dados do Postgres).

As variáveis em `.env` (copiadas de `.env.example`) controlam usuário/senha/nome do banco, porta e host do Postgres, e a porta/host/secret key da aplicação. Os defaults já funcionam out-of-the-box para desenvolvimento local.

### Rodando comandos `mix` dentro do container

Qualquer tarefa `mix` pode ser executada num container efêmero que reusa os mesmos volumes de dependências/build do serviço `app`, sem precisar instalar Elixir localmente:

```bash
docker compose run --rm app mix <tarefa>
```

Exemplos: `docker compose run --rm app mix ecto.migrate`, `docker compose run --rm app iex -S mix`.

## Login social com Google

Além de e-mail/senha, a tela `/sign-in` também oferece um botão "Entrar com Google" (issue #5, PRD §6.1, SDD §2.1 — estratégia `google` do `AshAuthentication`). Para habilitá-lo localmente:

1. No [Google Cloud Console](https://console.cloud.google.com/welcome), abra **APIs & Services → Credentials**.
2. Clique em **+ CREATE CREDENTIALS** e escolha **OAuth client ID**.
3. Em **Application type**, selecione **Web application**.
4. Em **Authorized redirect URIs**, adicione a URL de callback — a rota exata é gerada por `AshAuthentication.Phoenix` a partir do `auth_routes` no router e, para o ambiente `docker compose` local (`PHX_HOST=localhost`, `PORT=4000`), é:

   ```
   http://localhost:4000/auth/user/google/callback
   ```

   Para outro ambiente (produção, por exemplo), troque o host/porta pelo domínio real; o caminho (`/auth/user/google/callback`) não muda.
5. Copie o **Client ID** e o **Client secret** gerados e coloque-os em `.env` (nunca commitados — veja `.env.example`):

   ```
   GOOGLE_CLIENT_ID=...
   GOOGLE_CLIENT_SECRET=...
   ```

6. Reinicie `docker compose up` (ou `docker compose run --rm app ...`) para que as novas variáveis sejam lidas.

Sem essas duas variáveis definidas, o botão continua visível na tela de login, mas a troca do código OAuth por um token falha ao tentar autenticar (a aplicação não sobe com credenciais ausentes — apenas o fluxo de login Google não funciona). Em produção, defina também `GOOGLE_REDIRECT_URI` com a URL completa (`https://SEU-DOMINIO/auth`) caso o `PHX_HOST`/`PORT` calculados automaticamente (ver `config/runtime.exs`) não correspondam ao domínio público.

A suíte de testes automatizados nunca depende de credenciais reais do Google: o fluxo OAuth2 é exercitado ponta a ponta interceptando a troca de token e a busca de dados do usuário via um `Assent.HTTPAdapter` de teste (`test/support/google_oauth_stub.ex`), configurado apenas em `config/test.exs`.

## Rodando as verificações de qualidade localmente

Os comandos abaixo são os mesmos executados pela pipeline de CI (`.github/workflows/ci.yml`) em todo PR. Rode-os via `docker compose run --rm app <comando>` (sem Elixir instalado na máquina) ou diretamente com `mix` caso já tenha Elixir/Erlang no ambiente local (veja `mix.exs` para as versões usadas em CI: Elixir 1.18.3 / OTP 27).

| Verificação | Comando |
|---|---|
| Formatação (`mix format`) | `mix format --check-formatted` |
| Lint (`Credo`, modo estrito) | `mix credo --strict` |
| Análise estática (`Dialyzer`) | `mix dialyzer` |
| Testes | `mix test` |
| Testes com cobertura (`ExCoveralls`) | `mix coveralls` (ou `mix coveralls.html` para um relatório HTML em `cover/excoveralls.html`) |
| Tudo de uma vez (usado antes de commitar) | `mix precommit` |

Exemplo completo via Docker, do zero:

```bash
cp .env.example .env
docker compose up -d db
docker compose run --rm app mix deps.get
docker compose run --rm app mix format --check-formatted
docker compose run --rm app mix credo --strict
docker compose run --rm app mix dialyzer
docker compose run --rm -e MIX_ENV=test app sh -c "mix ecto.create && mix ecto.migrate && mix coveralls"
```

Notas:

* A primeira execução de `mix dialyzer` constrói o PLT (cacheado em `priv/plts/`, ignorado pelo git) e pode levar alguns minutos; execuções seguintes são rápidas. A pipeline de CI cacheia esse PLT entre execuções.
* `mix coveralls` usa a configuração em `coveralls.json`, com limiar mínimo de cobertura de 60% sobre o código de domínio/aplicação. Boilerplate gerado pelo `phx.new` que ainda não tem lógica própria (componentes de UI padrão, `Repo`, `Mailer`, `Endpoint`, etc.) fica listado em `skip_files` até que as issues de domínio (a partir da issue #1) tragam testes reais para esse código.
* `mix credo --strict` roda sem erros bloqueantes na base atual (restam apenas sugestões de baixa prioridade de design, que não falham o comando).

## Rodando sem Docker (Elixir/Erlang instalados localmente)

```bash
mix setup            # deps.get + ecto.setup + assets.setup + assets.build
mix phx.server        # ou: iex -S mix phx.server
```

Certifique-se de ter um PostgreSQL acessível localmente com as credenciais de `config/dev.exs` (por padrão `postgres`/`postgres` em `localhost:5432`), ou exporte `DATABASE_HOST`, `DATABASE_USER`, `DATABASE_PASSWORD` e `DATABASE_NAME` para apontar para outra instância.

## CI

Todo PR para `develop` ou `main` roda a pipeline `.github/workflows/ci.yml`, que sobe um serviço Postgres e executa, nessa ordem: `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict`, `mix dialyzer` e `mix coveralls.json` (publicando o relatório de cobertura como artifact do workflow).

## Fluxo de contribuição

Este repositório segue Git Flow simplificado (branches `feature/*` → `develop` → `main`) e usa o GitHub Issues/board como única fonte da verdade sobre o que precisa ser trabalhado. Veja `AGENTS.md` para o processo completo.

## Aprenda mais sobre Phoenix

* Site oficial: https://www.phoenixframework.org/
* Guias: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Fórum: https://elixirforum.com/c/phoenix-forum
