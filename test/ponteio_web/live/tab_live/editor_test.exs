defmodule PonteioWeb.TabLive.EditorTest do
  @moduledoc """
  Covers `GET /tabs/new` (issue #6) and `GET /tabs/:id/edit` (issue #8),
  PRD §6.2, SDD §7: both routes require an authenticated session, a
  signed-in user must be able to create/edit a tablature through the
  shared metadata form, and `:edit` must be scoped to the tab's owner.

  Field-level correctness of the created/updated record (capo_fret
  default, `status: :draft`, ownership via `relate_actor`, the `:update`
  action's own authorization) is covered directly against the resource in
  `Ponteio.Tablatures.TabCreateTest`/`TabUpdateTest` (SDD §6) — this module
  only asserts on the LiveView's own outputs (redirect, flash, pre-filled
  form, rendered errors).
  """

  use PonteioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ponteio.Accounts.User
  alias Ponteio.Tablatures.Tab

  test "redirects an unauthenticated visitor to /sign-in from /tabs/new", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/tabs/new")
  end

  test "redirects an unauthenticated visitor to /sign-in from /tabs/:id/edit", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(conn, ~p"/tabs/#{Ecto.UUID.generate()}/edit")
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

  describe "GET /tabs/:id/edit with an authenticated session" do
    setup :register_and_log_in_user

    test "renders the edit form pre-filled with the tab's current data", %{
      conn: conn,
      user: user
    } do
      tab = create_tab!(%{title: "Águas de Março", artist: "Tom Jobim", capo_fret: 2}, user)

      assert {:ok, _lv, html} = live(conn, ~p"/tabs/#{tab.id}/edit")

      assert html =~ "Editar tablatura"
      assert html =~ ~s(value="Águas de Março")
      assert html =~ ~s(value="Tom Jobim")
      assert html =~ ~s(value="2")
    end

    test "persists the edited metadata and redirects to /tabs on success", %{
      conn: conn,
      user: user
    } do
      tab = create_tab!(%{title: "Wave", artist: "Tom Jobim", capo_fret: 0}, user)

      {:ok, lv, _html} = live(conn, ~p"/tabs/#{tab.id}/edit")

      form_params = %{"title" => "Wave (revisada)", "artist" => "Tom Jobim", "capo_fret" => "3"}

      assert {:error, {:redirect, %{to: "/tabs"}}} =
               lv
               |> form("#tab-editor-form", form: form_params)
               |> render_submit()

      assert {:ok, reloaded} = Ash.get(Tab, tab.id, actor: user)
      assert reloaded.title == "Wave (revisada)"
      assert reloaded.capo_fret == 3
    end

    test "shows errors and stays on the page when title is cleared", %{conn: conn, user: user} do
      tab = create_tab!(%{title: "Wave", artist: "Tom Jobim"}, user)

      {:ok, lv, _html} = live(conn, ~p"/tabs/#{tab.id}/edit")

      form_params = %{"title" => "", "artist" => "Tom Jobim", "capo_fret" => "0"}

      html =
        lv
        |> form("#tab-editor-form", form: form_params)
        |> render_submit()

      assert html =~ "input-error"
      assert has_element?(lv, "#tab-editor-form")
    end

    test "raises a not-found error when the tab belongs to another user", %{conn: conn} do
      other_user = seed_user("outro@ponteio.app")
      their_tab = create_tab!(%{title: "Oceano", artist: "Djavan"}, other_user)

      assert_error_sent 404, fn ->
        live(conn, ~p"/tabs/#{their_tab.id}/edit")
      end
    end
  end

  defp seed_user(email) do
    {:ok, hashed_password} = AshAuthentication.BcryptProvider.hash("supersecret123")
    Ash.Seed.seed!(User, %{email: email, hashed_password: hashed_password})
  end

  defp create_tab!(params, actor) do
    Tab
    |> Ash.Changeset.for_create(:create, params, actor: actor)
    |> Ash.create!()
  end
end
