defmodule Ponteio.Accounts.UserIdentity do
  @moduledoc """
  Stores the `iss`/`sub` claims returned by an OAuth2 identity provider for
  each `Ponteio.Accounts.User` that authenticated through it (issue #5,
  SDD §2.1, `strategies :google`).

  Matching a returning user by e-mail alone is not safe for OAuth2/OIDC
  providers — only `iss` + `sub` uniquely and stably identify an end-user
  per spec. This resource is what `register_with_google` links to via
  `AshAuthentication.Strategy.OAuth2.IdentityChange`; it has no attributes
  of its own beyond what the `AshAuthentication.UserIdentity` extension
  generates.
  """

  use Ash.Resource,
    otp_app: :ponteio,
    domain: Ponteio.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication.UserIdentity]

  user_identity do
    user_resource Ponteio.Accounts.User
  end

  postgres do
    table "user_identities"
    repo Ponteio.Repo
  end
end
