defmodule Ponteio.Tablatures.TabUpsertMeasureNotesTest do
  @moduledoc """
  Covers `Tab`'s `:upsert_measure_notes` action (issue #14, "Salvar
  edições do editor e disparar recálculo de sugestões", PRD §6.4 regra 6;
  SDD §3.4, §5): the whole editor's compasso/nota tree — `TabLive.Editor`'s
  `@measures` shape — is persisted in one call, replacing whatever
  `Measure`/`Note` rows already existed for the tab, and `status` always
  ends up `:draft`.

  Issue #20's AshOban trigger (the thing that actually watches `status`
  and enqueues `:run_chord_analysis`) doesn't exist in this codebase yet —
  this module stops at the side effect this action is responsible for
  (setting `status: :draft`), not the trigger itself; see the PR for #14.
  """

  use Ponteio.DataCase, async: true

  require Ash.Query

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

  defp measures_of(tab, actor) do
    Measure
    |> Ash.Query.filter(tab_id == ^tab.id)
    |> Ash.Query.sort(position: :asc)
    |> Ash.Query.load(:notes)
    |> Ash.read!(actor: actor)
    |> Enum.map(fn measure -> %{measure | notes: Enum.sort_by(measure.notes, & &1.position)} end)
  end

  describe "upsert_measure_notes" do
    test "persists measures and notes from the editor's local state, in order" do
      owner = seed_user("dono@ponteio.app")
      tab = create_tab!(%{title: "Wave", artist: "Tom Jobim"}, owner)

      measures_params = [
        %{
          id: "measure-1",
          position: 1,
          notes: [
            %{string_number: 1, fret_number: 3, position: 0},
            %{string_number: 2, fret_number: 0, position: 1}
          ]
        },
        %{id: "measure-2", position: 2, notes: [%{string_number: 6, fret_number: 5, position: 0}]}
      ]

      assert {:ok, updated} =
               Ponteio.Tablatures.upsert_measure_notes(tab, measures_params, actor: owner)

      assert updated.status == :draft

      assert [measure_1, measure_2] = measures_of(tab, owner)

      assert measure_1.position == 1

      assert Enum.map(measure_1.notes, &{&1.string_number, &1.fret_number, &1.position}) == [
               {1, 3, 0},
               {2, 0, 1}
             ]

      assert measure_2.position == 2

      assert Enum.map(measure_2.notes, &{&1.string_number, &1.fret_number, &1.position}) == [
               {6, 5, 0}
             ]
    end

    test "an empty measures list is accepted — a lone, empty compasso has nothing to persist" do
      owner = seed_user("vazio@ponteio.app")
      tab = create_tab!(%{title: "Wave", artist: "Tom Jobim"}, owner)

      assert {:ok, _updated} = Ponteio.Tablatures.upsert_measure_notes(tab, [], actor: owner)
      assert measures_of(tab, owner) == []
    end

    test "a measure with no notes yet (an empty trailing compasso) is still persisted" do
      owner = seed_user("compassovazio@ponteio.app")
      tab = create_tab!(%{title: "Wave", artist: "Tom Jobim"}, owner)

      measures_params = [%{position: 1, notes: []}]

      assert {:ok, _updated} =
               Ponteio.Tablatures.upsert_measure_notes(tab, measures_params, actor: owner)

      assert [measure] = measures_of(tab, owner)
      assert measure.notes == []
    end

    test "saving again replaces the previous tree instead of accumulating rows" do
      owner = seed_user("substitui@ponteio.app")
      tab = create_tab!(%{title: "Wave", artist: "Tom Jobim"}, owner)

      first_params = [%{position: 1, notes: [%{string_number: 1, fret_number: 3, position: 0}]}]
      assert {:ok, _} = Ponteio.Tablatures.upsert_measure_notes(tab, first_params, actor: owner)

      second_params = [
        %{position: 1, notes: [%{string_number: 4, fret_number: 2, position: 0}]}
      ]

      assert {:ok, _} = Ponteio.Tablatures.upsert_measure_notes(tab, second_params, actor: owner)

      assert [measure] = measures_of(tab, owner)
      assert Enum.map(measure.notes, &{&1.string_number, &1.fret_number}) == [{4, 2}]
    end

    test "a non-owner is rejected with an authorization error, not a silent 404" do
      owner = seed_user("dono2@ponteio.app")
      intruder = seed_user("intruso2@ponteio.app")
      tab = create_tab!(%{title: "Oceano", artist: "Djavan"}, owner)

      measures_params = [
        %{position: 1, notes: [%{string_number: 1, fret_number: 0, position: 0}]}
      ]

      assert {:error, %Ash.Error.Forbidden{}} =
               Ponteio.Tablatures.upsert_measure_notes(tab, measures_params, actor: intruder)

      # Never partially applied — the intruder's attempt left no trace.
      assert measures_of(tab, owner) == []
    end
  end
end
