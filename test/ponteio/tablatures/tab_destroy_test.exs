defmodule Ponteio.Tablatures.TabDestroyTest do
  @moduledoc """
  Covers the `:destroy` action of `Ponteio.Tablatures.Tab` (issue #9, PRD
  §6.2): the owner can delete their own tablature through
  `Tablatures.delete_tab/2` (the code interface `TabLive.Index`'s "Excluir"
  row action uses), and the resource's `:destroy` policy rejects a
  non-owner rather than silently succeeding (SDD §2.2).
  """

  use Ponteio.DataCase, async: true

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

  describe "delete_tab/2" do
    test "the owner deletes their own tablature successfully" do
      user = seed_user("dono@ponteio.app")
      tab = create_tab!(%{title: "Wave", artist: "Tom Jobim"}, user)

      assert :ok = Tablatures.delete_tab(tab, actor: user)

      assert {:ok, []} = Tablatures.list_tabs_for_user(actor: user)
    end

    test "a non-owner is rejected with an authorization error, not a silent no-op" do
      owner = seed_user("dono2@ponteio.app")
      other = seed_user("outro2@ponteio.app")
      tab = create_tab!(%{title: "Wave", artist: "Tom Jobim"}, owner)

      assert {:error, error} = Tablatures.delete_tab(tab, actor: other)
      assert %Ash.Error.Forbidden{} = error

      # The tab still exists — the rejected destroy had no effect.
      assert {:ok, [remaining]} = Tablatures.list_tabs_for_user(actor: owner)
      assert remaining.id == tab.id
    end

    test "without an authenticated actor, the destroy is rejected" do
      user = seed_user("semactor@ponteio.app")
      tab = create_tab!(%{title: "Wave", artist: "Tom Jobim"}, user)

      assert {:error, error} = Tablatures.delete_tab(tab, actor: nil)
      assert %Ash.Error.Forbidden{} = error
    end
  end
end
