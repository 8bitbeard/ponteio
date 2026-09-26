defmodule Ponteio.Tablatures.ChordSuggestion do
  @moduledoc """
  One ranked chord candidate computed for a `ChordSegment` (issue #20,
  "Disparo assíncrono da análise de acordes com status visível"; PRD §6.4
  regra 3; SDD §2.2).

  Persists the output of `Ponteio.Chords.rank_candidates/2`: a
  `{chord_shape, base_fret}` pair (`Ponteio.Chords.candidate/0`) tagged
  with its `rank` (1 = best, up to 3) — see
  `Ponteio.Tablatures.Changes.RunChordAnalysis`, the only writer of this
  resource. A `:chorded` `ChordSegment` gets between 1 and 3 of these; a
  `:no_match` segment gets none (nothing to rank when
  `candidates_for_window/2` returned an empty list).

  `ChordSegment.selected_suggestion_id` (issue #21, "Usuário escolhe entre
  sugestões de acorde ambíguas") points back at one of a segment's own
  suggestions, set via `ChordSegment`'s `:select_chord_suggestion` action;
  this resource needed nothing extra to support that, since the
  relationship already lives on `ChordSegment`'s side (SDD §2.2).
  """

  use Ash.Resource,
    otp_app: :ponteio,
    domain: Ponteio.Tablatures,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "chord_suggestions"
    repo Ponteio.Repo

    references do
      # A `ChordSegment` re-analysis (`RunChordAnalysis`) destroys every
      # existing `ChordSuggestion` for the tab before recreating them, same
      # cascade rationale as `Measure`/`Note` for `Tab` — see their
      # `references` blocks. This also covers deleting a `Tab`/`Measure`
      # outright: the cascade reaches `ChordSuggestion` transitively via
      # `ChordSegment`.
      reference :chord_segment, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:chord_segment_id, :chord_shape_id, :base_fret, :rank]

      description """
      Persists one ranked candidate for a `ChordSegment` — called only from
      `Ponteio.Tablatures.Changes.RunChordAnalysis` (issue #20), never
      directly from a LiveView.
      """
    end
  end

  policies do
    # Same relationship-inheritance shape as `Measure`/`Note` (SDD §2.2,
    # issue #10), two hops further: a `ChordSuggestion` is only ever
    # accessible if the `chord_segment` it belongs to belongs to a
    # `measure` that belongs to a `tab` owned by the actor. `RunChordAnalysis`
    # (issue #20) creates these with `authorize?: false` (it's a
    # system-triggered background computation, not an actor-initiated
    # request — see that module's moduledoc), so this policy only ever
    # gates actor-driven reads (e.g. the eventual "Modo de estudo" LiveView,
    # issues #22/#23).
    policy action_type([:read, :destroy]) do
      authorize_if relates_to_actor_via([:chord_segment, :measure, :tab, :user])
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :base_fret, :integer do
      allow_nil? false
      public? true
      constraints min: 0

      description "Neck position the chord_shape was applied at (Ponteio.Chords.candidate/0's own base_fret)."
    end

    attribute :rank, :integer do
      allow_nil? false
      public? true
      constraints min: 1, max: 3

      description "1 = best candidate (least hand displacement), up to 3 (Ponteio.Chords.rank_candidates/2)."
    end

    timestamps()
  end

  relationships do
    belongs_to :chord_segment, Ponteio.Tablatures.ChordSegment do
      allow_nil? false
    end

    belongs_to :chord_shape, Ponteio.Chords.ChordShape do
      allow_nil? false
    end
  end
end
