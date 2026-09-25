defmodule Ponteio.Tablatures.NoteTest do
  @moduledoc """
  Covers `Ponteio.Tablatures.Note`'s actions and its policy (issue #11,
  "Inserir notas no editor de tablatura", PRD §6.3, SDD §2.2) — this
  issue's stated "Resource `Note`: `position` sequencial é preservado na
  ordem de inserção" expected test lives here, plus the `[:measure, :tab,
  :user]` policy inheritance pattern (issue #10).
  """

  use Ponteio.DataCase, async: true

  require Ash.Query

  alias Ponteio.Accounts.User
  alias Ponteio.Tablatures.Measure
  alias Ponteio.Tablatures.Note
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

  defp create_measure!(params, actor) do
    Measure
    |> Ash.Changeset.for_create(:create, params, actor: actor)
    |> Ash.create!()
  end

  defp create_note(params, opts) do
    Note
    |> Ash.Changeset.for_create(:create, params, opts)
    |> Ash.create()
  end

  defp create_note!(params, opts) do
    Note
    |> Ash.Changeset.for_create(:create, params, opts)
    |> Ash.create!()
  end

  describe "create" do
    test "creates a note for a measure reachable through the actor's own tab" do
      owner = seed_user("dono@ponteio.app")
      tab = create_tab!(%{title: "Wave", artist: "Tom Jobim"}, owner)
      measure = create_measure!(%{tab_id: tab.id, position: 1}, owner)

      assert {:ok, note} =
               create_note(
                 %{measure_id: measure.id, string_number: 1, fret_number: 3, position: 0},
                 actor: owner
               )

      assert note.measure_id == measure.id
      assert note.string_number == 1
      assert note.fret_number == 3
      assert note.position == 0
    end

    test "cannot create a note under another user's measure" do
      owner = seed_user("dono2@ponteio.app")
      intruder = seed_user("intruso2@ponteio.app")
      their_tab = create_tab!(%{title: "Oceano", artist: "Djavan"}, owner)
      their_measure = create_measure!(%{tab_id: their_tab.id, position: 1}, owner)

      assert {:error, _error} =
               create_note(
                 %{measure_id: their_measure.id, string_number: 1, fret_number: 0, position: 0},
                 actor: intruder
               )
    end

    test "rejects a string_number outside 1..6" do
      owner = seed_user("cordainvalida@ponteio.app")
      tab = create_tab!(%{title: "Wave", artist: "Tom Jobim"}, owner)
      measure = create_measure!(%{tab_id: tab.id, position: 1}, owner)

      assert {:error, error} =
               create_note(
                 %{measure_id: measure.id, string_number: 7, fret_number: 0, position: 0},
                 actor: owner
               )

      assert error_on_field?(error, :string_number)
    end

    test "rejects a negative fret_number" do
      owner = seed_user("casanegativa@ponteio.app")
      tab = create_tab!(%{title: "Wave", artist: "Tom Jobim"}, owner)
      measure = create_measure!(%{tab_id: tab.id, position: 1}, owner)

      assert {:error, error} =
               create_note(
                 %{measure_id: measure.id, string_number: 1, fret_number: -1, position: 0},
                 actor: owner
               )

      assert error_on_field?(error, :fret_number)
    end

    test "preserves sequential position in insertion order" do
      owner = seed_user("sequencia@ponteio.app")
      tab = create_tab!(%{title: "Wave", artist: "Tom Jobim"}, owner)
      measure = create_measure!(%{tab_id: tab.id, position: 1}, owner)

      first =
        create_note!(
          %{measure_id: measure.id, string_number: 1, fret_number: 3, position: 0},
          actor: owner
        )

      second =
        create_note!(
          %{measure_id: measure.id, string_number: 2, fret_number: 0, position: 1},
          actor: owner
        )

      third =
        create_note!(
          %{measure_id: measure.id, string_number: 4, fret_number: 2, position: 2},
          actor: owner
        )

      assert {:ok, notes} =
               Note
               |> Ash.Query.filter(measure_id == ^measure.id)
               |> Ash.Query.sort(position: :asc)
               |> Ash.read(actor: owner)

      assert Enum.map(notes, & &1.id) == [first.id, second.id, third.id]
      assert Enum.map(notes, & &1.position) == [0, 1, 2]
    end
  end

  describe "read/update/destroy policy" do
    test "a non-owner cannot read another user's note" do
      owner = seed_user("dono3@ponteio.app")
      intruder = seed_user("intruso3@ponteio.app")
      tab = create_tab!(%{title: "Wave", artist: "Tom Jobim"}, owner)
      measure = create_measure!(%{tab_id: tab.id, position: 1}, owner)

      note =
        create_note!(
          %{measure_id: measure.id, string_number: 1, fret_number: 0, position: 0},
          actor: owner
        )

      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}} =
               Ash.get(Note, note.id, actor: intruder)

      assert {:ok, _note} = Ash.get(Note, note.id, actor: owner)
    end

    test "a non-owner cannot update another user's note" do
      owner = seed_user("dono4@ponteio.app")
      intruder = seed_user("intruso4@ponteio.app")
      tab = create_tab!(%{title: "Wave", artist: "Tom Jobim"}, owner)
      measure = create_measure!(%{tab_id: tab.id, position: 1}, owner)

      note =
        create_note!(
          %{measure_id: measure.id, string_number: 1, fret_number: 0, position: 0},
          actor: owner
        )

      assert {:error, _error} =
               note
               |> Ash.Changeset.for_update(:update, %{fret_number: 5}, actor: intruder)
               |> Ash.update()
    end

    test "a non-owner cannot destroy another user's note" do
      owner = seed_user("dono5@ponteio.app")
      intruder = seed_user("intruso5@ponteio.app")
      tab = create_tab!(%{title: "Wave", artist: "Tom Jobim"}, owner)
      measure = create_measure!(%{tab_id: tab.id, position: 1}, owner)

      note =
        create_note!(
          %{measure_id: measure.id, string_number: 1, fret_number: 0, position: 0},
          actor: owner
        )

      assert {:error, _error} =
               note
               |> Ash.Changeset.for_destroy(:destroy, %{}, actor: intruder)
               |> Ash.destroy()

      assert {:ok, _note} = Ash.get(Note, note.id, actor: owner)
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
