defmodule PonteioWeb.PageControllerTest do
  use PonteioWeb.ConnCase

  test "GET / redirects to the tablatures list", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/tabs"
  end
end
