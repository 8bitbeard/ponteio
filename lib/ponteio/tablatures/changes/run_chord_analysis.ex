defmodule Ponteio.Tablatures.Changes.RunChordAnalysis do
  @moduledoc """
  Implements `Tab`'s `:run_chord_analysis` update action (issue #20,
  "Disparo assíncrono da análise de acordes com status visível"; PRD §6.4
  regra 6, §8; SDD §3.4) — the orchestration SDD §3.4's pseudocode
  describes, wired to the pure functions in `Ponteio.Chords` (issues
  #15-#17) and persisted as `ChordSegment`/`ChordSuggestion` rows.

  ## Why `tab.status` genuinely visits `:analyzing`, not just `:draft`/`:ready`

  A tablature can take perceptible time to analyze (PRD §8), and the whole
  point of this issue is that the UI can show "analisando..." *while*
  that's happening — not just before and after. That only works if the
  `:analyzing` status is a real, independently committed database write
  another connection (a LiveView's) can actually observe mid-flight, not
  merely an attribute this action's own changeset carries in memory until
  its single final commit.

  So this module does the status flip to `:analyzing` (`mark_tab!/2`) as
  its own separate `Ash.update!` call, immediately, before the analysis
  work starts — genuinely committed on its own, not nested inside
  whatever transaction `:run_chord_analysis` itself might open. For that
  to actually reach the database independently (rather than being folded
  into one all-encompassing transaction), the action below sets
  `transaction? false` and the `:analyze_chords` trigger sets
  `lock_for_update? false` — AshOban only wraps the read+lock+action call
  in its own transaction when *both* the action's `transaction?` and the
  trigger's `lock_for_update?` are true (`AshOban`'s own `work_transaction?`
  computation); disabling either is enough, this module disables both so
  the intent reads clearly from either file. The middle phase (deleting
  stale segments/suggestions and creating the new ones) is still wrapped
  in one `Ponteio.Repo.transaction/1` for atomicity — a crash partway
  through must not leave a half-deleted, half-recreated segment tree — and
  the final `status: :ready` write is `:run_chord_analysis`'s own action
  commit (a single `UPDATE`, still atomic on its own even without an
  explicit application-level transaction wrapper).

  ## Broadcasts

  `Phoenix.PubSub.broadcast(Ponteio.PubSub, "tab:\#{tab.id}", ...)` fires
  twice (SDD §3.4, this issue's "Testes esperados"): `:analyzing` right
  after that first independent commit, and `{:analysis_completed, tab.id}`
  once the whole action has actually finished — via
  `Ash.Changeset.after_transaction/2`, which runs after the final commit
  (or rollback) completes, precisely so a subscriber reacting to that
  second message by reloading `chord_segments`/`chord_suggestions` (issue
  #24, not yet implemented) never reads a not-yet-committed, half-written
  state.

  ## Authorization

  This whole pipeline runs with `authorize?: false` on every internal
  `Ash.read!`/`Ash.create!`/`Ash.destroy!`/`Ash.update!` call — it's a
  system-triggered background computation (no end-user actor initiated
  this specific write), not a request being made on anyone's behalf. The
  entry point itself (`:run_chord_analysis`, and the `where`-filtered read
  AshOban's scheduler/worker perform to find and fetch the `Tab`) is
  authorized instead by the `bypass AshOban.Checks.AshObanInteraction`
  policy at the top of `Tab`'s `policies` block — the mechanism `ash_oban`
  itself documents for exactly this case (no actor is available to a
  cron-driven trigger, and installing an `actor_persister` is unwarranted
  complexity here since this action's job is entirely determined by
  `tab.id`, never by *who* triggered it).

  ## Scope: selection preservation and capo are other issues' jobs

  This module does not try to match a new `ChordSegment` back to a
  previous run's segment to preserve `selected_suggestion_id` — that's
  issue #21's ("Usuário escolhe entre sugestões de acorde ambíguas") own
  stated scope, to be added here once `ChordSegment.select_chord_suggestion`
  exists. Nor does it do any capo arithmetic: `Note.fret_number` is already
  capo-relative (issue #11), and neither `Chords.candidates_for_window/2`
  nor `Chords.segment_measure/2` takes a capo argument at all — issue #19
  ("Considerar capotraste na análise de acordes") is about the *chord name*
  shown in the UI (`ChordShape.root_string` + `base_fret` + `tab.capo_fret`
  + standard tuning), not this module's matching/persistence logic.
  """

  use Ash.Resource.Change

  require Ash.Query

  alias Ponteio.Chords
  alias Ponteio.Chords.ChordShape
  alias Ponteio.Repo
  alias Ponteio.Tablatures.ChordSegment
  alias Ponteio.Tablatures.ChordSuggestion
  alias Ponteio.Tablatures.Measure

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, &run/1)
  end

  defp run(changeset) do
    tab = changeset.data

    mark_tab!(tab, :analyzing)
    broadcast(tab.id, :analyzing)

    reanalyze!(tab)

    changeset
    |> Ash.Changeset.force_change_attribute(:status, :ready)
    |> Ash.Changeset.after_transaction(&broadcast_completion/2)
  end

  # A standalone, independently-committed write — see this module's
  # moduledoc for why it must not be nested inside `:run_chord_analysis`'s
  # own commit.
  defp mark_tab!(tab, status) do
    tab
    |> Ash.Changeset.for_update(:mark_analyzing, %{}, authorize?: false)
    |> Ash.Changeset.force_change_attribute(:status, status)
    |> Ash.update!()
  end

  defp reanalyze!(tab) do
    {:ok, _} =
      Repo.transaction(fn ->
        chord_shapes = Ash.read!(ChordShape, authorize?: false)
        measures = load_measures!(tab)

        delete_previous_segments!(measures)
        analyze_measures!(measures, chord_shapes)
      end)

    :ok
  end

  defp load_measures!(tab) do
    Measure
    |> Ash.Query.filter(tab_id == ^tab.id)
    |> Ash.Query.sort(position: :asc)
    |> Ash.Query.load(:notes)
    |> Ash.read!(authorize?: false)
  end

  defp delete_previous_segments!(measures) do
    Enum.each(measures, fn measure ->
      ChordSegment
      |> Ash.Query.filter(measure_id == ^measure.id)
      |> Ash.read!(authorize?: false)
      |> Enum.each(&Ash.destroy!(&1, authorize?: false))
    end)
  end

  # Threads `previous_position` across the *whole song* (SDD §3.3) — the
  # accumulator carries from one measure's last segment into the next
  # measure's first, never resetting at a measure boundary. Starts at `0`
  # (open position), the documented default for the very first segment.
  defp analyze_measures!(measures, chord_shapes) do
    Enum.reduce(measures, 0, fn measure, previous_position ->
      analyze_measure!(measure, chord_shapes, previous_position)
    end)
  end

  defp analyze_measure!(measure, chord_shapes, previous_position) do
    notes = Enum.sort_by(measure.notes, & &1.position)

    notes
    |> Chords.segment_measure(chord_shapes)
    |> Enum.reduce(previous_position, fn segment, previous_position ->
      persist_segment!(measure, segment, previous_position)
    end)
  end

  defp persist_segment!(measure, %{status: :no_match} = segment, previous_position) do
    create_chord_segment!(measure, segment, :no_match)

    previous_position
  end

  defp persist_segment!(measure, %{status: :chorded} = segment, previous_position) do
    chord_segment = create_chord_segment!(measure, segment, :suggested)
    ranked = Chords.rank_candidates(segment.candidates, previous_position)

    Enum.each(ranked, &create_chord_suggestion!(chord_segment, &1))

    # The next segment's reference position is rank 1's own base_fret
    # (SDD §3.3) — computed during this same pass, never the user's
    # eventual manual pick (issue #21).
    case ranked do
      [%{base_fret: base_fret} | _] -> base_fret
      [] -> previous_position
    end
  end

  defp create_chord_segment!(measure, segment, status) do
    ChordSegment
    |> Ash.Changeset.for_create(
      :create,
      %{
        measure_id: measure.id,
        start_position: segment.start_position,
        end_position: segment.end_position,
        status: status
      },
      authorize?: false
    )
    |> Ash.create!()
  end

  defp create_chord_suggestion!(chord_segment, %{
         chord_shape: chord_shape,
         base_fret: base_fret,
         rank: rank
       }) do
    ChordSuggestion
    |> Ash.Changeset.for_create(
      :create,
      %{
        chord_segment_id: chord_segment.id,
        chord_shape_id: chord_shape.id,
        base_fret: base_fret,
        rank: rank
      },
      authorize?: false
    )
    |> Ash.create!()
  end

  defp broadcast_completion(_changeset, {:ok, tab} = result) do
    broadcast(tab.id, {:analysis_completed, tab.id})
    result
  end

  defp broadcast_completion(_changeset, result), do: result

  defp broadcast(tab_id, message) do
    Phoenix.PubSub.broadcast(Ponteio.PubSub, "tab:#{tab_id}", message)
  end
end
