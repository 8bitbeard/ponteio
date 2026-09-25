defmodule PonteioWeb.TabLive.IndexTest do
  @moduledoc """
  Covers `GET /tabs` — "Minhas tablaturas" (issue #7, PRD §6.2, SDD §7):
  besides the route-protection acceptance criteria from issue #3, this
  module asserts the listing itself only shows the authenticated user's own
  tablatures, each with title/artist/status and its row shortcuts (issue
  #7's stated test plan).

  The last test in "with an authenticated session" covers issue #10
  ("Isolamento de tablaturas por usuário"): a forged `"delete"` event
  naming another user's tab id must be rejected — flash error, no crash,
  no deletion — the same "explicit authorization denial" treatment
  `TabLive.Editor` gives a forged `/tabs/:id/edit`.
  """

  use PonteioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ponteio.Accounts.User
  alias Ponteio.Tablatures
  alias Ponteio.Tablatures.Tab

  test "redirects an unauthenticated visitor to /sign-in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/tabs")
  end

  describe "with an authenticated session" do
    setup :register_and_log_in_user

    test "renders the protected /tabs route", %{conn: conn} do
      assert {:ok, _lv, html} = live(conn, ~p"/tabs")
      assert html =~ "Minhas tablaturas"
    end

    test "shows an empty state when the user has no tabs", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/tabs")

      assert html =~ "Você ainda não tem nenhuma tablatura"
    end

    test "lists the user's own tabs with title, artist, capo and status, never another user's",
         %{conn: conn, user: user} do
      other_user = seed_user("outro@ponteio.app")

      create_tab!(%{title: "Águas de Março", artist: "Tom Jobim", capo_fret: 2}, user, :ready)
      create_tab!(%{title: "Oceano", artist: "Djavan"}, other_user, :draft)

      {:ok, lv, html} = live(conn, ~p"/tabs")

      assert html =~ "Águas de Março"
      assert html =~ "Tom Jobim"
      assert html =~ "Capo 2ª"
      assert html =~ "Pronta"
      refute html =~ "Oceano"
      refute html =~ "Djavan"

      assert has_element?(lv, "#tabs")
    end

    test "shows the three row shortcuts, with \"Estudar\" only for a ready tab", %{
      conn: conn,
      user: user
    } do
      ready = create_tab!(%{title: "Wave", artist: "Tom Jobim"}, user, :ready)
      draft = create_tab!(%{title: "Sem título", artist: "—"}, user, :draft)

      {:ok, lv, _html} = live(conn, ~p"/tabs")

      assert has_element?(lv, ~s{a[href="/tabs/#{ready.id}/study"]}, "Estudar")
      assert has_element?(lv, ~s{a[href="/tabs/#{ready.id}/edit"]}, "Editar")
      refute has_element?(lv, ~s{a[href="/tabs/#{draft.id}/study"]})
      assert has_element?(lv, ~s{a[href="/tabs/#{draft.id}/edit"]}, "Editar")

      assert has_element?(lv, ~s{a[phx-value-id="#{ready.id}"]}, "Excluir")
    end

    test "clicking \"Excluir\" deletes the tab and removes it from the list", %{
      conn: conn,
      user: user
    } do
      tab = create_tab!(%{title: "Wave", artist: "Tom Jobim"}, user, :ready)

      {:ok, lv, _html} = live(conn, ~p"/tabs")

      html =
        lv
        |> element(~s{a[phx-value-id="#{tab.id}"]}, "Excluir")
        |> render_click()

      assert html =~ "excluída"
      refute has_element?(lv, "#tabs")
      assert has_element?(lv, "#tabs-empty-state")
    end

    test "a forged \"delete\" for another user's tab id is rejected with a flash error, not a crash",
         %{conn: conn, user: user} do
      other_user = seed_user("outro@ponteio.app")
      their_tab = create_tab!(%{title: "Oceano", artist: "Djavan"}, other_user, :draft)

      {:ok, lv, _html} = live(conn, ~p"/tabs")

      # Bypasses the rendered row entirely (issue #10) — the same LiveView
      # event a tampered client could push regardless of what its own
      # "Excluir" link's `phx-value-id` says.
      html = render_click(lv, "delete", %{"id" => their_tab.id})

      assert html =~ "não tem permissão"

      # The other user's tab is untouched.
      assert {:ok, [remaining]} = Tablatures.list_tabs_for_user(actor: other_user)
      assert remaining.id == their_tab.id

      # And unrelated to the current user's own (empty) list.
      assert {:ok, []} = Tablatures.list_tabs_for_user(actor: user)
    end
  end

  defp seed_user(email) do
    {:ok, hashed_password} = AshAuthentication.BcryptProvider.hash("supersecret123")
    Ash.Seed.seed!(User, %{email: email, hashed_password: hashed_password})
  end

  defp create_tab!(params, actor, status) do
    tab =
      Tab
      |> Ash.Changeset.for_create(:create, params, actor: actor)
      |> Ash.create!()

    # `Tab`'s `:update` action (issue #8) only accepts `title`/`artist`/
    # `capo_fret` — `status` only ever moves via the chord-analysis workflow
    # (issue #20), so seed it directly on the record for this fixture's
    # non-draft cases.
    if status == :draft, do: tab, else: Ash.Seed.update!(tab, %{status: status})
  end
end
