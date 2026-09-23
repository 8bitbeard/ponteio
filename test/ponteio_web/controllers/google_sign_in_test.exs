defmodule PonteioWeb.GoogleSignInTest do
  @moduledoc """
  End-to-end HTTP coverage of the Google OAuth2 flow (issue #5, PRD §6.1,
  SDD §2.1/§7): `GET /auth/user/google` starts it, `GET
  /auth/user/google/callback` completes it, and the resulting session lets
  the user reach a protected route — all exercised exactly as a browser
  would, through `AshAuthentication.Phoenix.StrategyRouter` /
  `PonteioWeb.AuthController`, the same plumbing the "Entrar com Google"
  button on `/sign-in` (rendered once the `google` strategy is
  configured) links to.

  No real Google credentials or network access are involved: the token
  exchange and userinfo requests are intercepted by
  `Ponteio.Support.GoogleOAuthStub`, wired up as `config
  :ash_authentication, :http_adapter` in `config/test.exs`.

  `async: false` because the OAuth2 dance requires the session cookie set
  by the request-phase response to be replayed on the callback request
  (`recycle/1`), and mixing that with `ConnCase`'s SQL sandbox ownership
  transfer is simplest done serially for this one flow.
  """

  use PonteioWeb.ConnCase, async: false

  require Ash.Query

  alias Ponteio.Accounts.User
  alias Ponteio.Support.GoogleOAuthStub

  # `session_key` used by `AshAuthentication.Strategy.OAuth2.Plug` to stash
  # the CSRF `state` between the request and callback phases — see
  # `session_key/1` in that module ("#{subject_name}/#{strategy.name}").
  @session_key "user/google"

  defp start_flow(conn) do
    conn = get(conn, "/auth/user/google")
    %{state: state} = get_session(conn, @session_key)
    {conn, state}
  end

  test "GET /auth/user/google redirects to Google's authorize endpoint", %{conn: conn} do
    conn = get(conn, "/auth/user/google")

    assert location = redirected_to(conn, 302)
    assert location =~ "https://accounts.google.com/o/oauth2/v2/auth"
    assert location =~ "redirect_uri="
    assert get_session(conn, @session_key)[:state]
  end

  test "the callback creates a new user, signs them in, and grants access to protected routes",
       %{conn: conn} do
    email = "novo.usuario.google@example.com"
    {conn, state} = start_flow(conn)

    callback_conn =
      conn
      |> recycle()
      |> get("/auth/user/google/callback?code=#{GoogleOAuthStub.code_for(email)}&state=#{state}")

    assert redirected_to(callback_conn, 302) == "/"
    assert Phoenix.Flash.get(callback_conn.assigns.flash, :info) == "You are now signed in"

    user =
      User
      |> Ash.Query.filter(email == ^email)
      |> Ash.read_one!(authorize?: false)

    assert user
    assert user.confirmed_at != nil
    assert user.hashed_password == nil

    # the session AuthController.success/4 stored is enough to reach a
    # route behind `on_mount {PonteioWeb.LiveUserAuth, :live_user_required}`
    protected_conn =
      callback_conn
      |> recycle()
      |> get(~p"/tabs")

    assert html_response(protected_conn, 200)
  end

  test "signing in with Google twice for the same e-mail reuses the same account", %{conn: conn} do
    email = "repete.login.google@example.com"

    {conn1, state1} = start_flow(conn)

    conn1
    |> recycle()
    |> get("/auth/user/google/callback?code=#{GoogleOAuthStub.code_for(email)}&state=#{state1}")

    {conn2, state2} = start_flow(build_conn())

    conn2
    |> recycle()
    |> get("/auth/user/google/callback?code=#{GoogleOAuthStub.code_for(email)}&state=#{state2}")

    assert User
           |> Ash.Query.filter(email == ^email)
           |> Ash.count!(authorize?: false) == 1
  end

  test "a wrong/forged state is rejected instead of signing anyone in", %{conn: conn} do
    {conn, _state} = start_flow(conn)

    callback_conn =
      conn
      |> recycle()
      |> get(
        "/auth/user/google/callback?code=#{GoogleOAuthStub.code_for("forjado@example.com")}&state=not-the-real-state"
      )

    assert redirected_to(callback_conn, 302) == "/sign-in"
    assert Phoenix.Flash.get(callback_conn.assigns.flash, :error)

    refute User
           |> Ash.Query.filter(email == ^"forjado@example.com")
           |> Ash.exists?(authorize?: false)
  end
end
