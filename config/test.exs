import Config
config :ponteio, token_signing_secret: "rJ0A7NTJ5Mi76lnPqEwkjUH00oUD4m3I"
config :bcrypt_elixir, log_rounds: 1

# The Google OAuth2 flow (issue #5) never talks to the real Google API in
# tests — `Ponteio.Support.GoogleOAuthStub` intercepts the token exchange
# and userinfo requests that `AshAuthentication.Strategy.OAuth2.Plug`
# would otherwise send via `Assent.HTTPAdapter.Finch`.
config :ash_authentication, http_adapter: Ponteio.Support.GoogleOAuthStub
config :ash, policies: [show_policy_breakdowns?: true], disable_async?: true

# Oban's `:manual` testing mode (issue #20) disables the automatic
# queue/plugin supervisors — nothing runs in the background on its own.
# Tests instead call `AshOban.Test.schedule_and_run_triggers/2` (built on
# `Oban.Testing`) to schedule and drain the `:analyze_chords` trigger
# synchronously, deterministically, one test at a time.
config :ponteio, Oban, testing: :manual

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :ponteio, Ponteio.Repo,
  username: System.get_env("DATABASE_USER", "postgres"),
  password: System.get_env("DATABASE_PASSWORD", "postgres"),
  hostname: System.get_env("DATABASE_HOST", "localhost"),
  database:
    "#{System.get_env("DATABASE_NAME", "ponteio_test")}#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :ponteio, PonteioWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "XyEY9wKhBrHVdvxRquOQAl16ZzPVXqmaSpX2R3LwDW5nV9EFcrX24aKj1Ftxx4Ct",
  server: false

# In test we don't send emails
config :ponteio, Ponteio.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
