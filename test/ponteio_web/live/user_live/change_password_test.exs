defmodule PonteioWeb.UserLive.ChangePasswordTest do
  @moduledoc """
  Covers `GET /account/password` (issue #4, third acceptance criterion):
  the route must require an authenticated session, and a signed-in user
  must be able to change their current password through the form.
  """

  use PonteioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "redirects an unauthenticated visitor to /sign-in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/account/password")
  end

  describe "with an authenticated session" do
    setup :register_and_log_in_user

    test "renders the change password form", %{conn: conn} do
      assert {:ok, _lv, html} = live(conn, ~p"/account/password")

      assert html =~ "Trocar senha"
      assert html =~ ~s(type="password")
    end

    test "changes the password and redirects to /sign-in on success", %{
      conn: conn,
      password: password
    } do
      {:ok, lv, _html} = live(conn, ~p"/account/password")

      form_params = %{
        "current_password" => password,
        "password" => "novasenha789",
        "password_confirmation" => "novasenha789"
      }

      result =
        lv
        |> form("#change-password-form", form: form_params)
        |> render_submit()

      assert {:error, {:redirect, %{to: "/sign-in"}}} = result
    end

    test "shows an error and stays on the page with a wrong current password", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/account/password")

      form_params = %{
        "current_password" => "senha-totalmente-errada",
        "password" => "novasenha789",
        "password_confirmation" => "novasenha789"
      }

      html =
        lv
        |> form("#change-password-form", form: form_params)
        |> render_submit()

      assert html =~ "input-error"
      assert has_element?(lv, "#change-password-form")
    end
  end
end
