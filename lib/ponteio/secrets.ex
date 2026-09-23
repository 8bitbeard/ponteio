defmodule Ponteio.Secrets do
  @moduledoc """
  Resolves runtime secrets requested by `AshAuthentication` for
  `Ponteio.Accounts.User` — the token signing secret and, since issue #5,
  the Google OAuth2 client credentials and redirect URI — reading them
  from application config instead of hard-coding them into the resource.

  The Google values are populated in `config/runtime.exs` from the
  `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` environment variables (see
  `.env.example` and the README) — never committed as real values.
  """

  use AshAuthentication.Secret

  def secret_for(
        [:authentication, :tokens, :signing_secret],
        Ponteio.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:ponteio, :token_signing_secret)
  end

  def secret_for(
        [:authentication, :strategies, :google, :client_id],
        Ponteio.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:ponteio, :google_client_id)
  end

  def secret_for(
        [:authentication, :strategies, :google, :client_secret],
        Ponteio.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:ponteio, :google_client_secret)
  end

  def secret_for(
        [:authentication, :strategies, :google, :redirect_uri],
        Ponteio.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:ponteio, :google_redirect_uri)
  end
end
