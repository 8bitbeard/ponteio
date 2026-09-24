defmodule Ponteio.Tablatures.MeasureTest do
  @moduledoc """
  Covers `Ponteio.Tablatures.Measure`'s actions and its policy (issue #11,
  PRD §6.3, SDD §2.2): `Measure` was introduced as `Note`'s (this issue's
  actual "Resource novo") required parent, so its own actions and the
  `[:tab, :user]` inheritance pattern (issue #10) are exercised directly
  here, the same way `TabCreateTest`/`TabReadTest` exercise `Tab`.

  Nothing in this issue's LiveView calls these actions yet (see the
  resource's moduledoc) — this module is what stands in for issue #10's
  "for each dependent resource already existing" acceptance criterion
  ahead of #10 landing.
  """

  use Ponteio.DataCase, async: true

  alias Ponteio.Accounts.User
  alias Ponteio.Tablatures.Measure
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

  defp create_measure(params, opts) do
    Measure
    |> Ash.Changeset.for_create(:create, params, opts)
    |> Ash.create()
  end

  defp create_measure!(params, opts) do
    Measure
    |> Ash.Changeset.for_create(:create, params, opts)
    |> Ash.create!()
  end

  describe "create" do
    test "creates a measure for a tab owned by the actor" do
      owner = seed_user("dono@ponteio.app")
      tab = create_tab!(%{title: "Wave", artist: "Tom Jobim"}, owner)

      assert {:ok, measure} = create_measure(%{tab_id: tab.id, position: 1}, actor: owner)
      assert measure.tab_id == tab.id
      assert measure.position == 1
    end

    test "cannot create a measure under another user's tab" do
      owner = seed_user("dono2@ponteio.app")
      intruder = seed_user("intruso@ponteio.app")
      their_tab = create_tab!(%{title: "Oceano", artist: "Djavan"}, owner)

      assert {:error, _error} =
               create_measure(%{tab_id: their_tab.id, position: 1}, actor: intruder)
    end

    test "requires a position" do
      owner = seed_user("semposicao@ponteio.app")
      tab = create_tab!(%{title: "Wave", artist: "Tom Jobim"}, owner)

      assert {:error, error} = create_measure(%{tab_id: tab.id}, actor: owner)
      assert error_on_field?(error, :position)
    end
  end

  describe "read/update/destroy policy" do
    test "a non-owner cannot read another user's measure" do
      owner = seed_user("dono3@ponteio.app")
      intruder = seed_user("intruso3@ponteio.app")
      tab = create_tab!(%{title: "Wave", artist: "Tom Jobim"}, owner)
      measure = create_measure!(%{tab_id: tab.id, position: 1}, actor: owner)

      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}} =
               Ash.get(Measure, measure.id, actor: intruder)

      assert {:ok, _measure} = Ash.get(Measure, measure.id, actor: owner)
    end

    test "a non-owner cannot update another user's measure" do
      owner = seed_user("dono4@ponteio.app")
      intruder = seed_user("intruso4@ponteio.app")
      tab = create_tab!(%{title: "Wave", artist: "Tom Jobim"}, owner)
      measure = create_measure!(%{tab_id: tab.id, position: 1}, actor: owner)

      assert {:error, _error} =
               measure
               |> Ash.Changeset.for_update(:update, %{position: 2}, actor: intruder)
               |> Ash.update()
    end

    test "a non-owner cannot destroy another user's measure" do
      owner = seed_user("dono5@ponteio.app")
      intruder = seed_user("intruso5@ponteio.app")
      tab = create_tab!(%{title: "Wave", artist: "Tom Jobim"}, owner)
      measure = create_measure!(%{tab_id: tab.id, position: 1}, actor: owner)

      assert {:error, _error} =
               measure
               |> Ash.Changeset.for_destroy(:destroy, %{}, actor: intruder)
               |> Ash.destroy()

      assert {:ok, _measure} = Ash.get(Measure, measure.id, actor: owner)
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
