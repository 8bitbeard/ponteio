defmodule Ponteio.Accounts do
  @moduledoc """
  Domain for user accounts and authentication (per SDD §1, §2.1).

  Holds the `User` resource (backed by `AshAuthentication`, `strategies
  :password`) and its supporting `Token` resource. Social login
  (`strategies :google`) is added in a future issue, once that work is
  scoped.
  """

  use Ash.Domain,
    otp_app: :ponteio

  resources do
    resource Ponteio.Accounts.Token
    resource Ponteio.Accounts.User
  end
end
