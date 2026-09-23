defmodule Ponteio.Accounts do
  @moduledoc """
  Domain for user accounts and authentication (per SDD §1, §2.1).

  Holds the `User` resource (backed by `AshAuthentication`, `strategies
  :password` and `strategies :google`), its supporting `Token` resource,
  and the `UserIdentity` resource that links a `User` to the Google
  account(s) they signed in with (issue #5).
  """

  use Ash.Domain,
    otp_app: :ponteio

  resources do
    resource Ponteio.Accounts.Token
    resource Ponteio.Accounts.User
    resource Ponteio.Accounts.UserIdentity
  end
end
