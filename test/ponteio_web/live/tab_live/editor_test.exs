defmodule PonteioWeb.TabLive.EditorTest do
  @moduledoc """
  Covers `GET /tabs/new` (issue #6, PRD §6.2, SDD §7): the route must
  require an authenticated session, and a signed-in user must be able to
  create a tablature through the metadata form.

  Field-level correctness of the created record (capo_fret default,
  `status: :draft`, ownership via `relate_actor`) is covered directly
  against the `:create` action in `Ponteio.Tablatures.TabCreateTest` (SDD
  §6) — `Tab` has no `:read` action yet (added by issues #7/#10), so this
  module only asserts on the LiveView's own outputs (redirect, flash,
  rendered errors).
  """

  use PonteioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "redirects an unauthenticated visitor to /sign-in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/tabs/new")
  end

  describe "with an authenticated session" do
    setup :register_and_log_in_user

    test "renders the creation form", %{conn: conn} do
      assert {:ok, _lv, html} = live(conn, ~p"/tabs/new")

      assert html =~ "Nova tablatura"
      assert html =~ "Título"
      assert html =~ "Artista"
      assert html =~ "Capotraste"
    end

    test "creates the tablature and redirects to /tabs on success", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/tabs/new")

      form_params = %{"title" => "Águas de Março", "artist" => "Tom Jobim", "capo_fret" => "2"}

      assert {:error, {:redirect, %{to: "/tabs"}}} =
               lv
               |> form("#tab-editor-form", form: form_params)
               |> render_submit()
    end

    test "accepts 0 as a valid capotraste (no capo)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/tabs/new")

      form_params = %{"title" => "Wave", "artist" => "Tom Jobim", "capo_fret" => "0"}

      assert {:error, {:redirect, %{to: "/tabs"}}} =
               lv
               |> form("#tab-editor-form", form: form_params)
               |> render_submit()
    end

    test "shows errors and stays on the page when title/artist are missing", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/tabs/new")

      form_params = %{"title" => "", "artist" => "", "capo_fret" => "0"}

      html =
        lv
        |> form("#tab-editor-form", form: form_params)
        |> render_submit()

      assert html =~ "input-error"
      assert has_element?(lv, "#tab-editor-form")
    end
  end
end
