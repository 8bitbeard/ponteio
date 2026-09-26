defmodule Ponteio.Tablatures.Changes.SelectChordSuggestion do
  @moduledoc """
  Implements `ChordSegment`'s `:select_chord_suggestion` update action
  (issue #21, "Usuário escolhe entre sugestões de acorde ambíguas"; PRD
  §6.4 regra 3; SDD §5) — persists the user's pick among a segment's
  ranked `ChordSuggestion`s.

  Takes the whole `chord_suggestion` struct (not just its id) as an
  argument, per this issue's own code-interface contract
  (`select_chord_suggestion(chord_segment, chord_suggestion, actor:
  user)`), and validates ownership by comparing
  `chord_suggestion.chord_segment_id` against the segment being updated
  (`changeset.data.id`) — no extra read is needed since the caller already
  holds the suggestion row. A mismatch (a suggestion belonging to a
  *different* segment) fails the action with an `Ash.Error.Changes.InvalidArgument`
  instead of silently attaching the wrong id, per this issue's "Testes
  esperados".
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias Ash.Error.Changes.InvalidArgument

  @impl true
  def change(changeset, _opts, _context) do
    chord_suggestion = Changeset.get_argument(changeset, :chord_suggestion)
    chord_segment = changeset.data

    if chord_suggestion.chord_segment_id == chord_segment.id do
      Changeset.force_change_attribute(changeset, :selected_suggestion_id, chord_suggestion.id)
    else
      Changeset.add_error(
        changeset,
        InvalidArgument.exception(
          field: :chord_suggestion,
          message: "does not belong to this chord segment"
        )
      )
    end
  end
end
