defmodule PonteioWeb.TabLive.IndexTest do
  @moduledoc """
  Covers `GET /tabs` — "Minhas tablaturas" (issue #7, PRD §6.2, SDD §7):
  besides the route-protection acceptance criteria from issue #3, this
  module asserts the listing itself only shows the authenticated user's own
  tablatures, each with title/artist/status and its row shortcuts (issue
  #7's stated test plan).
  """

  use PonteioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ponteio.Accounts.User
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

    # `Tab` has no `:update` action yet (issue #8) to set `status` through —
    # seed it directly on the record for this fixture's non-draft cases.
    if status == :draft, do: tab, else: Ash.Seed.update!(tab, %{status: status})
  end
end
