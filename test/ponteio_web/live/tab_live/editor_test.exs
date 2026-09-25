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

  The "GET /tabs/:id/edit with an authenticated session" describe block's
  last two tests cover issue #10 ("Isolamento de tablaturas por usuário"):
  a non-owner's id (or an unknown one — the two must be indistinguishable
  from the caller's side, see `Ponteio.Tablatures.Tab`'s moduledoc) never
  reaches the edit form, and never crashes into a bare 404 either — it's
  redirected to `/tabs` with an explicit flash error.
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

    test "a non-owner is redirected to /tabs with a flash error, never a silent 404", %{
      conn: conn
    } do
      other_user = seed_user("outro@ponteio.app")
      their_tab = create_tab!(%{title: "Oceano", artist: "Djavan"}, other_user)

      assert {:error, {:redirect, %{to: "/tabs", flash: flash}}} =
               live(conn, ~p"/tabs/#{their_tab.id}/edit")

      assert flash["error"] =~ "não tem permissão"
    end

    test "an unknown id is redirected the same way, with the same flash", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/tabs", flash: flash}}} =
               live(conn, ~p"/tabs/#{Ecto.UUID.generate()}/edit")

      assert flash["error"] =~ "não tem permissão"
    end
  end

  describe "note-entry grid (issue #11)" do
    setup :register_and_log_in_user

    test "renders a single empty measure with its trailing cell clickable", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/tabs/new")

      assert html =~ "Compasso 1"
      assert has_element?(lv, "#cell-measure-1-1-0")
      refute has_element?(lv, "#note-input-measure-1-1")
    end

    test "clicking an empty trailing cell opens an inline fret input for that string", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/tabs/new")

      lv |> element("#cell-measure-1-1-0") |> render_click()

      assert has_element?(lv, "#note-input-measure-1-1")
    end

    test "confirming with Enter creates the note and opens a new trailing column", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/tabs/new")

      lv |> element("#cell-measure-1-1-0") |> render_click()

      html =
        lv
        |> element("#note-input-measure-1-1")
        |> render_keydown(%{"value" => "3"})

      refute html =~ ~s(id="note-input-measure-1-1")
      assert has_element?(lv, "#cell-measure-1-1-0", "3")
      assert has_element?(lv, "#cell-measure-1-1-1")
    end

    test "confirming on blur also creates the note", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/tabs/new")

      lv |> element("#cell-measure-1-2-0") |> render_click()

      lv
      |> element("#note-input-measure-1-2")
      |> render_blur(%{"value" => "0"})

      assert has_element?(lv, "#cell-measure-1-2-0", "0")
      assert has_element?(lv, "#cell-measure-1-2-1")
    end

    test "sequential notes land in sequential columns regardless of string", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/tabs/new")

      lv |> element("#cell-measure-1-1-0") |> render_click()
      lv |> element("#note-input-measure-1-1") |> render_keydown(%{"value" => "3"})

      lv |> element("#cell-measure-1-4-1") |> render_click()
      lv |> element("#note-input-measure-1-4") |> render_keydown(%{"value" => "2"})

      assert has_element?(lv, "#cell-measure-1-1-0", "3")
      assert has_element?(lv, "#cell-measure-1-4-1", "2")
      assert has_element?(lv, "#cell-measure-1-1-2")
    end

    test "an empty confirmation cancels without creating a note", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/tabs/new")

      lv |> element("#cell-measure-1-3-0") |> render_click()

      html =
        lv
        |> element("#note-input-measure-1-3")
        |> render_blur(%{"value" => ""})

      refute html =~ ~s(id="note-input-measure-1-3")
      refute has_element?(lv, "#cell-measure-1-3-1")
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
