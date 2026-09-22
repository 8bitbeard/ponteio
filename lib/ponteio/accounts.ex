defmodule Ponteio.Accounts do
  @moduledoc """
  Domain for user accounts and authentication (per SDD §1, §2.1).

  Intentionally empty in this foundational issue — the `User` resource
  (backed by `AshAuthentication`) is added in a future issue, once
  authentication work is scoped.
  """

  use Ash.Domain,
    otp_app: :ponteio

  resources do
  end
end
