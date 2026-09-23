defmodule PonteioWeb.TabLive.IndexTest do
  @moduledoc """
  Covers the acceptance criteria "Sessão autenticada dá acesso às rotas
  protegidas de `tabs`" from issue #3: `GET /tabs` (SDD §7) must redirect an
  unauthenticated visitor to `/sign-in`, and must be reachable by a session
  authenticated through the `:password` strategy.
  """

  use PonteioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "redirects an unauthenticated visitor to /sign-in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/tabs")
  end

  describe "with an authenticated session" do
    setup :register_and_log_in_user

    test "renders the protected /tabs route", %{conn: conn} do
      assert {:ok, _lv, html} = live(conn, ~p"/tabs")
      assert html =~ "Minhas tablaturas"
    end
  end
end
