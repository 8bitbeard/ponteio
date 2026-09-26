defmodule PonteioWeb.PageControllerTest do
  @moduledoc """
  Covers `GET /` (issue #48, PRD §6.1): a home própria da Ponteio para
  visitante não autenticado, com CTAs para `/sign-in` e `/register`, e o
  redirecionamento para `/tabs` quando já existe sessão ativa.
  """

  use PonteioWeb.ConnCase, async: true

  test "GET / without a session renders the visitor home with sign-in and register CTAs", %{
    conn: conn
  } do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ "Ponteio"
    assert html =~ ~s(href="/sign-in")
    assert html =~ ~s(href="/register")
    refute html =~ "Trocar senha"
    refute html =~ "Minhas tablaturas"
  end

  test "GET / with an active session redirects to /tabs", %{conn: conn} do
    conn = register_and_log_in_user(%{conn: conn}).conn
    conn = get(conn, ~p"/")

    assert redirected_to(conn) == ~p"/tabs"
  end
end
