defmodule Ponteio.Tablatures.TabReadTest do
  @moduledoc """
  Covers the `:read` action of `Ponteio.Tablatures.Tab` and its policy
  (issue #7, PRD §6.2, SDD §2.2): `list_tabs_for_user/1` (the code interface
  the "Minhas tablaturas" screen uses) must return only the actor's own
  tablatures, and the underlying policy must bar a direct `Ash.read` for
  another user's tab — issue #7's stated dependency on issue #10, which is
  not implemented yet.
  """

  use Ponteio.DataCase, async: true

  require Ash.Query

  alias Ponteio.Accounts.User
  alias Ponteio.Tablatures
  alias Ponteio.Tablatures.Tab

  defp seed_user(email) do
    {:ok, hashed_password} = AshAuthentication.BcryptProvider.hash("supersecret123")
    Ash.Seed.seed!(User, %{email: email, hashed_password: hashed_password})
  end

  defp create_tab!(params, actor) do
    Tab
    |> Ash.Changeset.for_create(:create, params, actor: actor)
    |> Ash.create!()
  end

  describe "list_tabs_for_user/1" do
    test "returns an empty list for a user with no tabs" do
      user = seed_user("semtabs@ponteio.app")

      assert {:ok, []} = Tablatures.list_tabs_for_user(actor: user)
    end

    test "returns only the actor's own tablatures, never another user's" do
      owner = seed_user("dono@ponteio.app")
      other = seed_user("outro@ponteio.app")

      mine = create_tab!(%{title: "Águas de Março", artist: "Tom Jobim"}, owner)
      _theirs = create_tab!(%{title: "Oceano", artist: "Djavan"}, other)

      assert {:ok, [tab]} = Tablatures.list_tabs_for_user(actor: owner)
      assert tab.id == mine.id
    end

    test "orders the most recently created tablature first" do
      owner = seed_user("ordem@ponteio.app")

      older = create_tab!(%{title: "Wave", artist: "Tom Jobim"}, owner)
      newer = create_tab!(%{title: "Chega de Saudade", artist: "Tom Jobim"}, owner)

      assert {:ok, [first, second]} = Tablatures.list_tabs_for_user(actor: owner)
      assert first.id == newer.id
      assert second.id == older.id
    end
  end

  describe "read policy" do
    test "a direct Ash.read for another user's tab never returns it, even by id" do
      owner = seed_user("dono2@ponteio.app")
      other = seed_user("outro2@ponteio.app")

      tab = create_tab!(%{title: "Wave", artist: "Tom Jobim"}, owner)

      assert {:ok, nil} =
               Tab
               |> Ash.Query.filter(id == ^tab.id)
               |> Ash.read_one(actor: other)
    end

    test "returns no tabs without an authenticated actor" do
      seed_user("semactor@ponteio.app") |> then(&create_tab!(%{title: "Wave", artist: "x"}, &1))

      assert {:ok, []} = Tablatures.list_tabs_for_user(actor: nil)
    end
  end
end
