defmodule Ponteio.Tablatures.TabUpdateTest do
  @moduledoc """
  Covers the `:update` action of `Ponteio.Tablatures.Tab` (issue #8, PRD
  §6.2): every acceptance criterion is exercised via `Ash.update/2`
  directly on the resource (SDD §6), the same call
  `PonteioWeb.TabLive.Editor`'s `AshPhoenix.Form` makes for `:edit`.
  """

  use Ponteio.DataCase, async: true

  alias Ponteio.Accounts.User
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

  defp update_tab(tab, params, opts) do
    tab
    |> Ash.Changeset.for_update(:update, params, opts)
    |> Ash.update()
  end

  describe "update" do
    test "the owner edits title, artist and capo_fret successfully" do
      user = seed_user("dono@ponteio.app")
      tab = create_tab!(%{title: "Wave", artist: "Tom Jobim", capo_fret: 0}, user)

      assert {:ok, updated} =
               update_tab(
                 tab,
                 %{title: "Águas de Março", artist: "Tom Jobim/Elizete", capo_fret: 3},
                 actor: user
               )

      assert updated.title == "Águas de Março"
      assert updated.artist == "Tom Jobim/Elizete"
      assert updated.capo_fret == 3
    end

    test "changing capo_fret alone doesn't touch title/artist/status" do
      user = seed_user("capo@ponteio.app")
      tab = create_tab!(%{title: "Wave", artist: "Tom Jobim", capo_fret: 0}, user)

      assert {:ok, updated} = update_tab(tab, %{capo_fret: 5}, actor: user)

      assert updated.capo_fret == 5
      assert updated.title == "Wave"
      assert updated.artist == "Tom Jobim"
      assert updated.status == :draft
    end

    test "a non-owner is rejected with an authorization error, not a silent 404" do
      owner = seed_user("dono2@ponteio.app")
      other = seed_user("outro2@ponteio.app")
      tab = create_tab!(%{title: "Wave", artist: "Tom Jobim"}, owner)

      assert {:error, error} = update_tab(tab, %{title: "Hackeado"}, actor: other)
      assert %Ash.Error.Forbidden{} = error
    end

    test "requires a title" do
      user = seed_user("semtitulo@ponteio.app")
      tab = create_tab!(%{title: "Wave", artist: "Tom Jobim"}, user)

      assert {:error, error} = update_tab(tab, %{title: nil}, actor: user)
      assert error_on_field?(error, :title)
    end

    test "rejects a negative capo_fret" do
      user = seed_user("caponegativo@ponteio.app")
      tab = create_tab!(%{title: "Wave", artist: "Tom Jobim"}, user)

      assert {:error, error} = update_tab(tab, %{capo_fret: -1}, actor: user)
      assert error_on_field?(error, :capo_fret)
    end

    test "rejects a submitted status — it never moves through :update" do
      user = seed_user("statusforcado@ponteio.app")
      tab = create_tab!(%{title: "Wave", artist: "Tom Jobim"}, user)

      assert {:error, error} = update_tab(tab, %{status: :ready}, actor: user)

      assert %Ash.Error.Invalid.NoSuchInput{input: :status} =
               Enum.find(error.errors, &match?(%Ash.Error.Invalid.NoSuchInput{}, &1))
    end

    test "rejects a submitted user_id — ownership never changes via :update" do
      user = seed_user("dono3@ponteio.app")
      other = seed_user("outro3@ponteio.app")
      tab = create_tab!(%{title: "Wave", artist: "Tom Jobim"}, user)

      assert {:error, error} = update_tab(tab, %{user_id: other.id}, actor: user)

      assert %Ash.Error.Invalid.NoSuchInput{input: :user_id} =
               Enum.find(error.errors, &match?(%Ash.Error.Invalid.NoSuchInput{}, &1))
    end
  end

  defp error_on_field?(%{errors: errors}, field) when is_list(errors) do
    Enum.any?(errors, fn error -> Map.get(error, :field) == field end)
  end

  defp error_on_field?(error, field) when is_exception(error) do
    error
    |> List.wrap()
    |> Enum.any?(fn e -> Map.get(e, :field) == field end)
  end
end
