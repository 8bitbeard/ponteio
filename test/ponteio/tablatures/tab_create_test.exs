defmodule Ponteio.Tablatures.TabCreateTest do
  @moduledoc """
  Covers the `:create` action of `Ponteio.Tablatures.Tab` (issue #6, PRD
  §6.2): every acceptance criterion is exercised via `Ash.create/2`
  directly on the resource (SDD §6), the same call
  `PonteioWeb.TabLive.Editor`'s `AshPhoenix.Form` makes.
  """

  use Ponteio.DataCase, async: true

  alias Ponteio.Accounts.User
  alias Ponteio.Tablatures.Tab

  defp seed_user(email \\ "compositor@ponteio.app") do
    {:ok, hashed_password} = AshAuthentication.BcryptProvider.hash("supersecret123")
    Ash.Seed.seed!(User, %{email: email, hashed_password: hashed_password})
  end

  defp create_tab(params, opts) do
    Tab
    |> Ash.Changeset.for_create(:create, params, opts)
    |> Ash.create()
  end

  describe "create" do
    test "creates a tablature owned by the actor, born as a draft" do
      user = seed_user()

      assert {:ok, tab} =
               create_tab(%{title: "Águas de Março", artist: "Tom Jobim", capo_fret: 2},
                 actor: user
               )

      assert tab.title == "Águas de Março"
      assert tab.artist == "Tom Jobim"
      assert tab.capo_fret == 2
      assert tab.status == :draft
      assert tab.user_id == user.id
    end

    test "accepts capo_fret 0 (no capo) as the default when omitted" do
      user = seed_user("semcapo@ponteio.app")

      assert {:ok, tab} =
               create_tab(%{title: "Wave", artist: "Tom Jobim"}, actor: user)

      assert tab.capo_fret == 0
    end

    test "requires a title" do
      user = seed_user("semtitulo@ponteio.app")

      assert {:error, error} = create_tab(%{artist: "Tom Jobim"}, actor: user)
      assert error_on_field?(error, :title)
    end

    test "requires an artist" do
      user = seed_user("semartista@ponteio.app")

      assert {:error, error} = create_tab(%{title: "Wave"}, actor: user)
      assert error_on_field?(error, :artist)
    end

    test "rejects a negative capo_fret" do
      user = seed_user("caponegativo@ponteio.app")

      assert {:error, error} =
               create_tab(%{title: "Wave", artist: "Tom Jobim", capo_fret: -1}, actor: user)

      assert error_on_field?(error, :capo_fret)
    end

    test "rejects a submitted status — :draft is never user-settable" do
      user = seed_user("statusforcado@ponteio.app")

      assert {:error, error} =
               create_tab(
                 %{title: "Wave", artist: "Tom Jobim", status: :ready},
                 actor: user
               )

      assert %Ash.Error.Invalid.NoSuchInput{input: :status} =
               Enum.find(error.errors, &match?(%Ash.Error.Invalid.NoSuchInput{}, &1))
    end

    test "rejects a submitted user_id — ownership only comes from the actor" do
      user = seed_user("dono@ponteio.app")
      other_user = seed_user("outro@ponteio.app")

      assert {:error, error} =
               create_tab(
                 %{title: "Wave", artist: "Tom Jobim", user_id: other_user.id},
                 actor: user
               )

      assert %Ash.Error.Invalid.NoSuchInput{input: :user_id} =
               Enum.find(error.errors, &match?(%Ash.Error.Invalid.NoSuchInput{}, &1))
    end

    test "cannot create without an authenticated actor" do
      assert {:error, %Ash.Error.Invalid{}} =
               create_tab(%{title: "Wave", artist: "Tom Jobim"}, actor: nil)
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
