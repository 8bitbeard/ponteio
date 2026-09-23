defmodule PonteioWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use PonteioWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  alias AshAuthentication.Plug.Helpers, as: AuthPlugHelpers
  alias Ponteio.Accounts.User

  using do
    quote do
      # The default endpoint for testing
      @endpoint PonteioWeb.Endpoint

      use PonteioWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import PonteioWeb.ConnCase
    end
  end

  setup tags do
    Ponteio.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Seeds a `Ponteio.Accounts.User` and authenticates `context.conn` as that
  user, per the `AshAuthentication` testing guide ("Testing authenticated
  LiveViews"): seed the user, sign in through the `:password` strategy
  action to obtain a token, then `store_in_session/2`.

  Usable as a `setup` callback (`setup :register_and_log_in_user`) or called
  directly from a test with the test context.
  """
  def register_and_log_in_user(%{conn: conn} = context) do
    email = Map.get(context, :email, "usuario@ponteio.app")
    password = Map.get(context, :password, "supersecret123")

    {:ok, hashed_password} = AshAuthentication.BcryptProvider.hash(password)

    user =
      Ash.Seed.seed!(User, %{
        email: email,
        hashed_password: hashed_password
      })

    strategy = AshAuthentication.Info.strategy!(User, :password)

    {:ok, signed_in_user} =
      AshAuthentication.Strategy.action(strategy, :sign_in, %{
        email: email,
        password: password
      })

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> AuthPlugHelpers.store_in_session(signed_in_user)

    %{context | conn: conn} |> Map.put(:user, user) |> Map.put(:password, password)
  end
end
