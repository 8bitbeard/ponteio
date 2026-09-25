defmodule Ponteio.Tablatures.Tab do
  @moduledoc """
  A tablature's metadata: title, artist, and capo position, plus the status
  the UI uses to know when chord analysis is pending (per PRD §6.2, SDD
  §2.2).

  Issue #6 ("Criar nova tablatura") implemented `:create`. Issue #7
  ("Listar minhas tablaturas") added `:read`, plus the read policy that
  keeps the listing scoped to its owner. Issue #8 ("Editar metadados de
  uma tablatura") added `:update`, and this issue (#9, "Excluir
  tablatura") adds `:destroy` — both guarded by that same
  `user_id == actor(:id)` shape, anticipating issue #10 ("Isolamento de
  tablaturas por usuário"), which formalizes the equivalent policy
  project-wide.

  There is nothing to cascade at the database level yet for `:destroy`:
  `Measure`, `Note`, `ChordSegment` and `ChordSuggestion` don't exist as
  resources until the `epic:editor`/`epic:chord-engine` issues that
  introduce them — each of those is expected to declare its
  `belongs_to :tab` with `on_delete: :delete_all` in its migration (this
  issue's stated scope), so deleting a `Tab` removes its whole tree
  without this issue needing to touch anything beyond the `Tab` resource
  itself.

  Issue #10 ("Isolamento de tablaturas por usuário") formalized the
  `user_id == actor(:id)` shape below as the project-wide policy pattern
  (SDD §2.2, §7) and established how `Measure`, `Note`, `ChordSegment` and
  `ChordSuggestion` must inherit it once each exists: not by repeating a
  `user_id` comparison (they don't carry that column), but through their
  relationship path back to `Tab` — e.g. `Measure`, via
  `authorize_if relates_to_actor_via([:tab, :user])`; `Note`, via
  `[:measure, :tab, :user]`; `ChordSegment`/`ChordSuggestion`, via their own
  relationship chain to `Tab`. None of those resources exist in the
  codebase yet (`epic:editor`/`epic:chord-engine`), so there is nothing to
  apply that pattern to beyond this resource for now — the issue is scoped
  to `Tab` plus this documented pattern for whichever of those resources
  lands first.

  Issue #14 ("Salvar edições do editor e disparar recálculo de sugestões")
  added `:upsert_measure_notes` — the action `TabLive.Editor`'s
  `phx-submit` calls to persist the whole compasso/nota tree the editor
  built up as local assigns (issues #11-#13) and flip `status` back to
  `:draft`, in one transaction (PRD §6.4 regra 6; SDD §3.4, §5). See its
  own description for the persistence rule.
  """

  use Ash.Resource,
    otp_app: :ponteio,
    domain: Ponteio.Tablatures,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    # The primary (and, for now, only) `:read` action carries a `sort`
    # preparation on purpose — it's the listing order for issue #7's
    # "Minhas tablaturas" screen, and there is no secondary read action to
    # move it to. Harmless for the internal uses (policy checks, relationship
    # loading) Ash's default warning is guarding against here.
    primary_read_warning?: false

  postgres do
    table "tabs"
    repo Ponteio.Repo
  end

  actions do
    create :create do
      primary? true
      accept [:title, :artist, :capo_fret]

      description "Creates a tablature owned by the authenticated actor (issue #6)."

      # The owner is always the authenticated actor — never a manually
      # selected/submitted value (SDD §2.2's `change relate_actor(:user)`).
      change relate_actor(:user)
    end

    read :read do
      primary? true

      description """
      Lists tablatures for the "Minhas tablaturas" screen (issue #7, PRD
      §6.2). Scoping to the authenticated actor's own tabs is enforced
      entirely by the policy below — this action applies no manual
      `user_id` filter (SDD §2.2, §5's `list_tabs_for_user/1`).
      """

      prepare build(sort: [inserted_at: :desc])
    end

    update :update do
      primary? true
      accept [:title, :artist, :capo_fret]

      description """
      Edits a tablature's metadata — title, artist, capo position (issue
      #8, PRD §6.2). `status` and `user_id` are never accepted here, same
      as `:create` — ownership doesn't change on edit, and `status` only
      ever moves via the chord-analysis workflow (issue #20).

      Changing `capo_fret` is an isolated mutation: it doesn't touch
      existing `Measure`/`Note` rows, nor clear any `ChordSegment`/
      `ChordSuggestion` already computed. The next `:run_chord_analysis`
      run (issue #20, triggered by issue #14 on editor save) is what reads
      the current `capo_fret` and produces suggestions consistent with it.
      """
    end

    destroy :destroy do
      primary? true

      description """
      Deletes a tablature (issue #9, PRD §6.2). Cascading removal of
      `Measure`/`Note`/`ChordSegment`/`ChordSuggestion` is out of scope
      here — none of those resources exist yet, and each is expected to
      declare its own `belongs_to :tab` with `on_delete: :delete_all` in
      its migration once introduced, so the database itself takes care
      of the cascade without additional code in this action.
      """
    end

    update :upsert_measure_notes do
      accept []
      require_atomic? false

      description """
      Persists `TabLive.Editor`'s entire compasso/nota tree in one
      transaction and marks the tab `status: :draft` (issue #14, PRD §6.4
      regra 6; SDD §3.4, §5) — called once, on `phx-submit`, never per
      keystroke (SDD §3.4's "não a cada tecla digitada"). The `:draft`
      status is the side effect issue #20's AshOban trigger (not yet
      implemented) will watch for to enqueue `:run_chord_analysis`
      automatically; this action's job stops at setting it.

      `measures` replaces the tab's whole `Measure`/`Note` tree —
      `Ponteio.Tablatures.Changes.UpsertMeasureNotes` destroys every
      existing `Measure` (cascading to its `Note`s at the database level)
      and recreates the submitted list fresh, which is correct either way
      since the editor always submits the complete current picture, never
      a diff (issues #11-#13).
      """

      argument :measures, {:array, :map} do
        allow_nil? false
        default []

        description """
        One entry per compasso, in playing order: `%{position: pos,
        notes: [%{string_number:, fret_number:, position:}, ...]}` — the
        same shape `TabLive.Editor` keeps as `@measures` (its `:id` key,
        a purely local editor/DOM handle, is ignored here; persisted
        `Measure`/`Note` rows get their own generated ids).
        """
      end

      change set_attribute(:status, :draft)
      change Ponteio.Tablatures.Changes.UpsertMeasureNotes
    end
  end

  policies do
    # Only an authenticated actor may create a tablature — it is always
    # related to that actor via `relate_actor(:user)` above, so there is no
    # "create on behalf of someone else" case to guard against here.
    policy action(:create) do
      authorize_if actor_present()
    end

    # A tablature is only ever readable by its owner (SDD §2.2, issue #10's
    # canonical shape) so `:read`/`list_tabs_for_user` never expose another
    # user's tablatures (issue #7's stated dependency on #10). This is a
    # `:filter`-access-type check (the default) — Ash folds it into the
    # query rather than raising, so a non-owner's `Ash.get/3` by id comes
    # back `{:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}}`
    # (indistinguishable from a truly unknown id), never the row itself.
    # `TabLive.Editor`/`TabLive.Index` are the callers that turn that into
    # a flash + redirect instead of a silent crash (issue #10).
    policy action_type(:read) do
      authorize_if expr(user_id == ^actor(:id))
    end

    # A tablature is only ever editable by its owner (SDD §2.2, issue #8's
    # stated dependency on #10) — same shape as the read policy above, so a
    # non-owner's `:update` is rejected with a policy/authorization error
    # rather than silently succeeding or looking like a 404 (issue #8's
    # explicit acceptance criterion). `action_type(:update)` also covers
    # `:upsert_measure_notes` (issue #14) for free — it's an `update`
    # action too, so a non-owner is rejected here before
    # `Changes.UpsertMeasureNotes` ever touches a `Measure`/`Note`.
    policy action_type(:update) do
      authorize_if expr(user_id == ^actor(:id))
    end

    # A tablature is only ever deletable by its owner (SDD §2.2, issue #9's
    # explicit acceptance criterion) — same shape as the read policy above,
    # so a non-owner's `:destroy` is rejected with a policy/authorization
    # error rather than silently succeeding.
    policy action_type(:destroy) do
      authorize_if expr(user_id == ^actor(:id))
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
      description "Required (PRD §6.2)."
    end

    attribute :artist, :string do
      allow_nil? false
      public? true
      description "Required (PRD §6.2)."
    end

    attribute :capo_fret, :integer do
      allow_nil? false
      public? true
      default 0
      constraints min: 0
      description "Capo position; 0 means no capo (PRD §6.2, SDD §2.2)."
    end

    attribute :status, :atom do
      allow_nil? false
      public? true
      default :draft
      constraints one_of: [:draft, :analyzing, :ready]

      description """
      Reflects whether AshOban chord-analysis is pending/running, so the UI
      can show "analisando..." in study mode (SDD §2.2). Always :draft on
      creation — never accepted directly from user input.
      """
    end

    timestamps()
  end

  relationships do
    belongs_to :user, Ponteio.Accounts.User do
      allow_nil? false
    end

    has_many :measures, Ponteio.Tablatures.Measure
  end
end
