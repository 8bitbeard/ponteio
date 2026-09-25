defmodule Ponteio.Tablatures.Changes.UpsertMeasureNotes do
  @moduledoc """
  Implements `Tab`'s `:upsert_measure_notes` update action (issue #14, PRD
  §6.4 regra 6; SDD §3.4, §5): replaces the tab's entire `Measure`/`Note`
  tree with the `:measures` argument, in the same database transaction as
  the `status: :draft` attribute change that action's `set_attribute`
  change makes.

  `TabLive.Editor` already keeps the *complete* current picture of a
  tablature's compassos/notas as local assigns (issues #11-#13) and
  submits that whole picture on save, never a diff — so "replace
  everything" (destroy every existing `Measure`, which cascades to its
  `Note`s at the database level per `Measure`'s `references` block, then
  create the submitted list fresh) is the simplest semantics that's
  correct for both a brand-new tablature (no existing `Measure` rows to
  destroy) and an edit of one that already has some.

  Runs from `Ash.Changeset.before_action/2` so it executes inside the same
  repo transaction `AshPostgres.DataLayer` opens for the `Tab` update
  itself (Ash's documented "changes inside `before_action`/`after_action`
  share the action's transaction" behavior) — a failure partway through
  (an invalid note, a policy violation) rolls back the `status` change and
  every `Measure`/`Note` write alike, leaving the tab exactly as it was
  before the save.
  """

  use Ash.Resource.Change

  alias Ponteio.Tablatures.Measure
  alias Ponteio.Tablatures.Note

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, &replace_measures(&1, context.actor))
  end

  defp replace_measures(changeset, actor) do
    tab = changeset.data
    measures_params = Ash.Changeset.get_argument(changeset, :measures) || []

    destroy_existing_measures!(tab, actor)
    create_measures!(tab, measures_params, actor)

    changeset
  end

  defp destroy_existing_measures!(tab, actor) do
    Measure
    |> Ash.Query.filter(tab_id == ^tab.id)
    |> Ash.read!(actor: actor)
    |> Enum.each(&Ash.destroy!(&1, actor: actor))
  end

  defp create_measures!(tab, measures_params, actor) do
    Enum.each(measures_params, fn measure_params ->
      measure =
        Measure
        |> Ash.Changeset.for_create(
          :create,
          %{tab_id: tab.id, position: fetch(measure_params, :position)},
          actor: actor
        )
        |> Ash.create!()

      create_notes!(measure, fetch(measure_params, :notes) || [], actor)
    end)
  end

  defp create_notes!(measure, notes_params, actor) do
    Enum.each(notes_params, fn note_params ->
      Note
      |> Ash.Changeset.for_create(
        :create,
        %{
          measure_id: measure.id,
          string_number: fetch(note_params, :string_number),
          fret_number: fetch(note_params, :fret_number),
          position: fetch(note_params, :position)
        },
        actor: actor
      )
      |> Ash.create!()
    end)
  end

  # `TabLive.Editor` always calls this action with its own atom-keyed
  # `@measures`/`@measures[].notes` shape, but this also tolerates
  # string-keyed maps (e.g. params that crossed a JSON boundary) rather
  # than assuming one shape and crashing on the other.
  defp fetch(map, key) when is_map(map) do
    Map.get(map, key, Map.get(map, to_string(key)))
  end
end
