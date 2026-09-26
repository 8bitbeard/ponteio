defmodule Ponteio.Tablatures.TabRunChordAnalysisTest do
  @moduledoc """
  Covers `Tab`'s `:analyze_chords` AshOban trigger and the
  `:run_chord_analysis` action it fires (issue #20, "Disparo assíncrono da
  análise de acordes com status visível"; PRD §6.4 regra 6, §8; SDD §3.4)
  — the workflow issue #14's `TabUpsertMeasureNotesTest` moduledoc
  explicitly deferred to this PR.

  Uses `AshOban.Test.schedule_and_run_triggers/2` (config/test.exs sets
  `config :ponteio, Oban, testing: :manual`) to schedule and drain the
  `:analyze_chords` trigger synchronously, so the whole
  scheduler-finds-the-tab -> worker-runs-the-action pipeline executes
  in-process, deterministically, once per test.
  """

  use Ponteio.DataCase, async: false

  require Ash.Query

  alias Ponteio.Accounts.User
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

  # A single-string, open-position shape that only ever matches a lone
  # note on `string_number` at `fret_number` — deliberately narrow so
  # tests control exactly which notes are "chorded" vs. "sem sugestão".
  defp seed_chord_shape!(slug, string_number, fret_number) do
    relative_frets = List.duplicate(nil, 6) |> List.replace_at(string_number - 1, fret_number)

    Ash.Seed.seed!(ChordShape, %{
      slug: slug,
      name: "Maior",
      quality: :major,
      root_string: string_number,
      relative_frets: relative_frets,
      movable: false,
      min_base_fret: 0,
      max_base_fret: 0
    })
  end

  defp chord_segments_of(measure) do
    ChordSegment
    |> Ash.Query.filter(measure_id == ^measure.id)
    |> Ash.Query.sort(start_position: :asc)
    |> Ash.Query.load(:chord_suggestions)
    |> Ash.read!(authorize?: false)
  end

  defp run_trigger! do
    AshOban.Test.schedule_and_run_triggers({Tab, :analyze_chords})
  end

  describe "the :analyze_chords trigger" do
    test "matches a :draft tab and persists segments/suggestions, ending :ready" do
      owner = seed_user("dono@ponteio.app")
      # Matches a lone note on string 1, fret 3.
      seed_chord_shape!("shape-1-3", 1, 3)

      tab = create_tab!(%{title: "Wave", artist: "Tom Jobim"}, owner)

      measure =
        Measure
        |> Ash.Changeset.for_create(:create, %{tab_id: tab.id, position: 1}, authorize?: false)
        |> Ash.create!()

      # position 0 matches the seeded shape (:chorded); position 1 (string
      # 2) matches nothing, falling back to a lone :no_match segment
      # (issues #16/#18).
      Note
      |> Ash.Changeset.for_create(
        :create,
        %{measure_id: measure.id, string_number: 1, fret_number: 3, position: 0},
        authorize?: false
      )
      |> Ash.create!()

      Note
      |> Ash.Changeset.for_create(
        :create,
        %{measure_id: measure.id, string_number: 2, fret_number: 5, position: 1},
        authorize?: false
      )
      |> Ash.create!()

      assert %{success: 2, failure: 0} = run_trigger!()

      updated_tab = Ash.get!(Tab, tab.id, authorize?: false)
      assert updated_tab.status == :ready

      assert [segment_1, segment_2] = chord_segments_of(measure)

      assert segment_1.start_position == 0
      assert segment_1.end_position == 0
      assert segment_1.status == :suggested
      assert [%{rank: 1, base_fret: 0}] = segment_1.chord_suggestions

      assert segment_2.start_position == 1
      assert segment_2.end_position == 1
      assert segment_2.status == :no_match
      assert segment_2.chord_suggestions == []
    end

    test "also matches a tab stuck in :analyzing (a previous run that never finished)" do
      owner = seed_user("preso@ponteio.app")
      seed_chord_shape!("shape-preso", 1, 0)

      tab = create_tab!(%{title: "Oceano", artist: "Djavan"}, owner)
      tab = Ash.Seed.update!(tab, %{status: :analyzing})

      assert %{success: 2, failure: 0} = run_trigger!()

      assert Ash.get!(Tab, tab.id, authorize?: false).status == :ready
    end

    test "does not match an already :ready tab" do
      owner = seed_user("pronto@ponteio.app")
      tab = create_tab!(%{title: "Chega de Saudade", artist: "Tom Jobim"}, owner)
      Ash.Seed.update!(tab, %{status: :ready})

      # Only the scheduler job runs (and succeeds, finding nothing to
      # enqueue) — no worker job for a tab the trigger's `where` excludes.
      assert %{success: 1, failure: 0} = run_trigger!()
    end

    test "re-running replaces stale segments/suggestions instead of accumulating them" do
      owner = seed_user("substitui@ponteio.app")
      seed_chord_shape!("shape-substitui", 1, 2)

      tab = create_tab!(%{title: "Águas de Março", artist: "Tom Jobim"}, owner)

      measure =
        Measure
        |> Ash.Changeset.for_create(:create, %{tab_id: tab.id, position: 1}, authorize?: false)
        |> Ash.create!()

      Note
      |> Ash.Changeset.for_create(
        :create,
        %{measure_id: measure.id, string_number: 1, fret_number: 2, position: 0},
        authorize?: false
      )
      |> Ash.create!()

      assert %{success: 2} = run_trigger!()
      assert [first_run_segment] = chord_segments_of(measure)

      Ash.Seed.update!(Ash.get!(Tab, tab.id, authorize?: false), %{status: :draft})
      assert %{success: 2} = run_trigger!()

      assert [second_run_segment] = chord_segments_of(measure)
      # A fresh row, not the same one mutated in place — RunChordAnalysis
      # always deletes-then-recreates (SDD §3.4), never updates existing
      # ChordSegment rows.
      assert second_run_segment.id != first_run_segment.id
    end

    test "broadcasts :analyzing then {:analysis_completed, tab_id} on the tab's topic" do
      owner = seed_user("broadcast@ponteio.app")
      seed_chord_shape!("shape-broadcast", 1, 0)
      tab = create_tab!(%{title: "Wave", artist: "Tom Jobim"}, owner)

      Phoenix.PubSub.subscribe(Ponteio.PubSub, "tab:#{tab.id}")

      assert %{success: 2} = run_trigger!()

      assert_received :analyzing
      tab_id = tab.id
      assert_received {:analysis_completed, ^tab_id}
    end
  end
end
