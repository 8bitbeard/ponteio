defmodule Ponteio.Tablatures.Note do
  @moduledoc """
  A single string/fret position within a `Measure`, in the sequence it
  should be played (issue #11, "Inserir notas no editor de tablatura";
  PRD §6.3; SDD §2.2). This is this issue's actual "Resource novo".

  `string_number` follows the same 1–6 (high E .. low E) convention as
  `Ponteio.Chords.ChordShape.root_string`. `fret_number` is **relative to
  the capo** defined on the parent `Tab`'s `capo_fret` — `0` means "at the
  capo", not "open string" (PRD §6.3's acceptance criterion; the
  chord-analysis engine, issue #19, is what applies `capo_fret` when
  comparing against the chord catalog — this resource just stores the
  relative value). `position` is the note's order of insertion within its
  measure — issue #11's acceptance criterion that ordering follows
  insertion sequence, not any inherent musical timing (the editor
  captures no rhythm/duration in Fase 1).

  As with `Measure` (see its moduledoc), no LiveView calls this resource's
  actions directly yet — issue #11's editor keeps inserted notes as local
  assigns, and `upsert_measure_notes` (issue #14) is what will eventually
  persist them in bulk. The actions/policy here make the resource usable
  and independently testable (this issue's "Resource `Note`: `position`
  sequencial é preservado na ordem de inserção" expected test) ahead of
  that.
  """

  use Ash.Resource,
    otp_app: :ponteio,
    domain: Ponteio.Tablatures,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "notes"
    repo Ponteio.Repo

    references do
      # Deleting a `Measure` (and transitively, its `Tab`) removes its
      # `Note`s at the database level (same cascade rationale as `Measure`
      # for `Tab` — see its `references` block).
      reference :measure, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:measure_id, :string_number, :fret_number, :position]
    end

    update :update do
      primary? true
      accept [:string_number, :fret_number, :position]
    end
  end

  policies do
    # Same inheritance shape as `Measure` (SDD §2.2, issue #10), one hop
    # further: a `Note` is only ever accessible/mutable if the `measure` it
    # belongs to belongs to a `tab` owned by the actor. Covers `:create`
    # too via Ash's post-insert filter-create behavior (see `Measure`'s
    # moduledoc/policy comment for how that works).
    policy action_type([:create, :read, :update, :destroy]) do
      authorize_if relates_to_actor_via([:measure, :tab, :user])
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :string_number, :integer do
      allow_nil? false
      public? true
      constraints min: 1, max: 6

      description """
      Which string this note is fretted on (1 = high E/"e" .. 6 = low
      E/"E"), same convention as `ChordShape.root_string`.
      """
    end

    attribute :fret_number, :integer do
      allow_nil? false
      public? true
      constraints min: 0

      description """
      Fret position, relative to the parent tab's capo — 0 means "at the
      capo's position", not necessarily the open string (PRD §6.3).
      """
    end

    attribute :position, :integer do
      allow_nil? false
      public? true
      constraints min: 0

      description """
      Order of insertion within the measure (0-based) — the editor's grid
      column index, not a musical time value (issue #11: no rhythm/duration
      captured).
      """
    end

    timestamps()
  end

  relationships do
    belongs_to :measure, Ponteio.Tablatures.Measure do
      allow_nil? false
    end
  end
end
