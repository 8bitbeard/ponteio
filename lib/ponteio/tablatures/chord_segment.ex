defmodule Ponteio.Tablatures.ChordSegment do
  @moduledoc """
  One contiguous stretch of a `Measure`'s notes resolved to either a set of
  chord candidates or "sem sugestão" by the chord-analysis engine (issue
  #20, "Disparo assíncrono da análise de acordes com status visível"; PRD
  §6.4; SDD §2.2).

  Persists one entry of `Ponteio.Chords.segment_measure/2`'s result list
  (a `Ponteio.Chords.segment/0`) — `start_position`/`end_position` are that
  segment's own note positions (within the measure, inclusive on both
  ends), and `status` mirrors the segment's own `:chorded`/`:no_match` tag,
  translated to this resource's `:suggested`/`:no_match` (SDD §2.2's
  naming: a "chorded" segment always gets ranked, persisted
  `ChordSuggestion`s, hence "suggested" once it's a database row).

  `Ponteio.Tablatures.Changes.RunChordAnalysis` (issue #20) deletes every
  `ChordSegment` for a tab and recreates the current analysis result fresh
  on each run (SDD §3.4's "apaga chord_segments/chord_suggestions antigos
  do tab") — it is still the only writer of `:create`/`:destroy`, and (as
  of issue #21) also the module that carries a matching previous
  `selected_suggestion_id` forward across re-runs when the new segment is
  equivalent to one from the prior run (same `measure_id` +
  `start_position`/`end_position`).

  Issue #21 ("Usuário escolhe entre sugestões de acorde ambíguas") added
  `:select_chord_suggestion`, the only *actor-driven* update action here —
  it exclusively touches `selected_suggestion_id`, never anything else on
  this resource.
  """

  use Ash.Resource,
    otp_app: :ponteio,
    domain: Ponteio.Tablatures,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "chord_segments"
    repo Ponteio.Repo

    references do
      # Deleting a `Measure` (and transitively its `Tab`) removes its
      # `ChordSegment`s at the database level — same cascade rationale as
      # `Measure`/`Note` for `Tab` (see their `references` blocks).
      reference :measure, on_delete: :delete

      # `selected_suggestion_id` points at one of *this segment's own*
      # `ChordSuggestion` rows (issue #21's `:select_chord_suggestion`) —
      # nil until the user picks one. `on_delete: :nilify` rather than
      # `:delete`: destroying a suggestion (e.g. the next `RunChordAnalysis`
      # run clearing old ones) must not cascade into destroying the segment
      # that happened to reference it, just clear the pick.
      reference :selected_suggestion, on_delete: :nilify
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:measure_id, :start_position, :end_position, :status]

      description """
      Persists one resolved segment for a measure — called only from
      `Ponteio.Tablatures.Changes.RunChordAnalysis` (issue #20), never
      directly from a LiveView. `selected_suggestion_id` is never accepted
      here (issue #21's `:select_chord_suggestion` is the only way it's
      ever set, aside from `RunChordAnalysis`'s own reanalysis-preservation
      copy).
      """
    end

    update :select_chord_suggestion do
      accept []
      require_atomic? false

      argument :chord_suggestion, :struct do
        allow_nil? false
        constraints instance_of: Ponteio.Tablatures.ChordSuggestion

        description """
        The candidate the user picked among this segment's own
        `chord_suggestions` — must belong to this `ChordSegment` (its
        `chord_segment_id` must match), or the action fails.
        """
      end

      description """
      Persists the user's chosen candidate among this segment's ranked
      suggestions (issue #21, "Usuário escolhe entre sugestões de acorde
      ambíguas"; PRD §6.4 regra 3; SDD §5) — the code interface behind the
      `chord-chip` selector in the study screen (issues #22/#23, not this
      issue's scope). Fails with an `Ash.Error.Changes.InvalidArgument` if
      `chord_suggestion` does not belong to this segment. Preserved across
      a later re-analysis only when the new segment is equivalent to this
      one (same `measure_id` + `start_position`/`end_position` — see
      `Ponteio.Tablatures.Changes.RunChordAnalysis`); otherwise the new
      segment starts unselected (defaults to displaying rank 1).
      """

      change Ponteio.Tablatures.Changes.SelectChordSuggestion
    end
  end

  policies do
    # Same relationship-inheritance shape as `Measure`/`Note` (SDD §2.2,
    # issue #10), one hop further than `Measure`: a `ChordSegment` is only
    # ever accessible if the `measure` it belongs to belongs to a `tab`
    # owned by the actor. `RunChordAnalysis` (issue #20) creates/destroys
    # these with `authorize?: false` (a system-triggered background
    # computation, not an actor-initiated request — see that module's
    # moduledoc), so this policy only ever gates actor-driven reads (e.g.
    # the eventual "Modo de estudo" LiveView, issues #22/#23) and
    # `:destroy`.
    policy action_type([:read, :destroy]) do
      authorize_if relates_to_actor_via([:measure, :tab, :user])
    end

    # `:select_chord_suggestion` (issue #21) is the one `:update` action
    # here that *is* actor-driven (the user picking a candidate in study
    # mode) — same ownership shape as the read/destroy policy above.
    policy action_type(:update) do
      authorize_if relates_to_actor_via([:measure, :tab, :user])
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :start_position, :integer do
      allow_nil? false
      public? true
      constraints min: 0
      description "First note position (within the measure) this segment covers, inclusive."
    end

    attribute :end_position, :integer do
      allow_nil? false
      public? true
      constraints min: 0
      description "Last note position (within the measure) this segment covers, inclusive."
    end

    attribute :status, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:suggested, :no_match]

      description """
      `:suggested` when at least one chord candidate matched (this
      segment's ChordSuggestions carry them); `:no_match` when
      `Ponteio.Chords.segment_measure/2` fell back to an unmatched, lone
      note (PRD §6.4 regra 4, issue #18) — no ChordSuggestion exists for a
      `:no_match` segment.
      """
    end

    timestamps()
  end

  relationships do
    belongs_to :measure, Ponteio.Tablatures.Measure do
      allow_nil? false
    end

    belongs_to :selected_suggestion, Ponteio.Tablatures.ChordSuggestion do
      allow_nil? true

      description """
      The user's chosen candidate among this segment's suggestions, set by
      `:select_chord_suggestion` (issue #21) or carried forward across a
      re-analysis by `RunChordAnalysis` when the segment is equivalent to
      one from the prior run. Nil otherwise (the UI then defaults to
      displaying rank 1).
      """
    end

    has_many :chord_suggestions, Ponteio.Tablatures.ChordSuggestion
  end
end
