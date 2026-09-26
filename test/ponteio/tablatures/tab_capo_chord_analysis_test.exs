defmodule Ponteio.Tablatures.TabCapoChordAnalysisTest do
  @moduledoc """
  Covers issue #19 ("Considerar capotraste na análise de acordes"; PRD
  §6.4 regra 5; SDD §2.2, §2.3) end to end: `Note.fret_number` is already
  capo-relative (issue #11), so `:run_chord_analysis` (issue #20) matches
  and ranks identically regardless of `Tab.capo_fret` — this file asserts
  that invariant holds through the real trigger/action pipeline (not just
  the pure `Ponteio.Chords` functions, covered directly in
  `Ponteio.ChordsTest`), and that `Chords.root_note_name/3` is what
  actually varies with the capo, per this issue's own "Testes esperados".

  Same `AshOban.Test.schedule_and_run_triggers/2` harness as
  `Ponteio.Tablatures.TabRunChordAnalysisTest`.
  """

  use Ponteio.DataCase, async: false

  require Ash.Query

  alias Ponteio.Accounts.User
  alias Ponteio.Chords
  alias Ponteio.Chords.ChordShape
  alias Ponteio.Tablatures.ChordSegment
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

  # E maior aberto, mesma forma usada em Ponteio.ChordsTest: casa nas
  # cordas 1, 2 e 6 na casa 0 (relativa ao capo).
  defp seed_e_major_open! do
    Ash.Seed.seed!(ChordShape, %{
      slug: "e-major-open-capo-test",
      name: "Maior",
      quality: :major,
      root_string: 6,
      relative_frets: [0, 0, 1, 2, 2, 0],
      movable: false,
      min_base_fret: 0,
      max_base_fret: 0
    })
  end

  defp create_measure_with_e_major_notes!(tab) do
    measure =
      Measure
      |> Ash.Changeset.for_create(:create, %{tab_id: tab.id, position: 1}, authorize?: false)
      |> Ash.create!()

    for {string_number, position} <- [{1, 0}, {2, 1}, {6, 2}] do
      Note
      |> Ash.Changeset.for_create(
        :create,
        %{
          measure_id: measure.id,
          string_number: string_number,
          fret_number: 0,
          position: position
        },
        authorize?: false
      )
      |> Ash.create!()
    end

    measure
  end

  defp chord_segments_of(measure) do
    ChordSegment
    |> Ash.Query.filter(measure_id == ^measure.id)
    |> Ash.Query.sort(start_position: :asc)
    |> Ash.Query.load(chord_suggestions: [:chord_shape])
    |> Ash.read!(authorize?: false)
  end

  defp run_trigger! do
    AshOban.Test.schedule_and_run_triggers({Tab, :analyze_chords})
  end

  test "same relative notes with different capo_fret produce the same segment/suggestion but a different root note name" do
    owner = seed_user("capo-invariante@ponteio.app")
    seed_e_major_open!()

    tab_no_capo = create_tab!(%{title: "Sem capo", artist: "Teste", capo_fret: 0}, owner)
    tab_with_capo = create_tab!(%{title: "Com capo", artist: "Teste", capo_fret: 3}, owner)

    measure_no_capo = create_measure_with_e_major_notes!(tab_no_capo)
    measure_with_capo = create_measure_with_e_major_notes!(tab_with_capo)

    # Not asserting an exact `success` count here (unlike
    # `TabRunChordAnalysisTest`'s sibling assertions): this issue is about
    # capo/naming correctness, not the trigger's job-scheduling mechanics
    # (issue #20's own scope) — only `failure: 0` (the whole pipeline ran
    # clean for both tabs) matters to this test.
    assert %{failure: 0} = run_trigger!()

    assert [segment_no_capo] = chord_segments_of(measure_no_capo)
    assert [segment_with_capo] = chord_segments_of(measure_with_capo)

    # Same window, same catalog -> same match: identical status/base_fret/
    # chord_shape regardless of Tab.capo_fret, since Note.fret_number is
    # already capo-relative (issue #11) and the matching/ranking pipeline
    # never looks at capo_fret at all.
    assert segment_no_capo.status == segment_with_capo.status
    assert [%{base_fret: base_fret, chord_shape: chord_shape}] = segment_no_capo.chord_suggestions

    assert [%{base_fret: ^base_fret, chord_shape: ^chord_shape}] =
             segment_with_capo.chord_suggestions

    # But the *named* root note reflects each tab's own capo_fret.
    assert Chords.root_note_name(chord_shape, base_fret, tab_no_capo.capo_fret) == "Mi"
    assert Chords.root_note_name(chord_shape, base_fret, tab_with_capo.capo_fret) == "Sol"
  end

  test "changing a tab's capo_fret and reanalyzing keeps producing the same suggestion, named consistently with the new capo" do
    owner = seed_user("capo-muda@ponteio.app")
    seed_e_major_open!()

    tab = create_tab!(%{title: "Capo muda", artist: "Teste", capo_fret: 0}, owner)
    measure = create_measure_with_e_major_notes!(tab)

    assert %{failure: 0} = run_trigger!()
    assert [first_segment] = chord_segments_of(measure)
    assert [%{base_fret: base_fret, chord_shape: chord_shape}] = first_segment.chord_suggestions
    assert Chords.root_note_name(chord_shape, base_fret, tab.capo_fret) == "Mi"

    tab
    |> Ash.Changeset.for_update(:update, %{capo_fret: 2}, actor: owner)
    |> Ash.update!()

    Ash.Seed.update!(Ash.get!(Tab, tab.id, authorize?: false), %{status: :draft})
    assert %{failure: 0} = run_trigger!()

    updated_tab = Ash.get!(Tab, tab.id, authorize?: false)
    assert updated_tab.capo_fret == 2

    assert [second_segment] = chord_segments_of(measure)

    assert [%{base_fret: ^base_fret, chord_shape: ^chord_shape}] =
             second_segment.chord_suggestions

    assert Chords.root_note_name(chord_shape, base_fret, updated_tab.capo_fret) == "Fá#"
  end
end
