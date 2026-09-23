defmodule Ponteio.Secrets do
  @moduledoc """
  Resolves runtime secrets requested by `AshAuthentication` (currently
  just the token signing secret for `Ponteio.Accounts.User`), reading them
  from application config instead of hard-coding them into a resource.
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
end
