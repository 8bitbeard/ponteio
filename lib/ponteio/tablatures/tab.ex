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

  Issue #20 ("Disparo assíncrono da análise de acordes com status
  visível") added `ChordSegment`/`ChordSuggestion` (closing the gap issues
  #10/#14 above anticipated), the `extensions: [AshOban]` `oban do
  triggers do trigger :analyze_chords do ... end end` block that watches
  `status`, and the `:mark_analyzing`/`:run_chord_analysis` actions that
  block drives — see `Ponteio.Tablatures.Changes.RunChordAnalysis` for the
  actual orchestration.
  """

  use Ash.Resource,
    otp_app: :ponteio,
    domain: Ponteio.Tablatures,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshOban],
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

  oban do
    triggers do
      # Fires `:run_chord_analysis` (issue #20) whenever a tab is left
      # `:draft` (freshly saved by `:upsert_measure_notes`, issue #14) or
      # `:analyzing` (a previous run that never made it to `:ready` — a
      # crashed/killed job — gets picked up again the next time the
      # scheduler polls, since the actual persisted status never advanced
      # past `:analyzing` for it). SDD §3.4's own pseudocode.
      trigger :analyze_chords do
        action :run_chord_analysis
        where expr(status == :draft or status == :analyzing)
        queue(:tab_analyze_chords)
        read_action :ready_for_chord_analysis

        # See `Ponteio.Tablatures.Changes.RunChordAnalysis`'s moduledoc
        # ("Why tab.status genuinely visits :analyzing") for why this must
        # be `false`: AshOban only wraps the read+lock+action call in its
        # own transaction when this is `true` *and* the action's own
        # `transaction?` is `true` — either one being `false` is enough to
        # let that action's internal early `:analyzing` write commit on
        # its own, independently of the action's final commit.
        lock_for_update?(false)

        # Explicit, stable module names (`mix ash_oban.set_default_module_names`'s
        # own suggestion) — renaming the trigger or the resource later
        # won't orphan whatever jobs Oban already persisted under these.
        worker_module_name(Ponteio.Tablatures.Tab.AshOban.Worker.AnalyzeChords)
        scheduler_module_name(Ponteio.Tablatures.Tab.AshOban.Scheduler.AnalyzeChords)
      end
    end
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

    read :ready_for_chord_analysis do
      description """
      Dedicated read action for the `:analyze_chords` AshOban trigger
      (issue #20) — `ash_oban` requires the trigger's read action to
      support keyset pagination, which the primary `:read` above (issue
      #7's "Minhas tablaturas" listing) has no reason to be configured
      for. Filtering by `status` is entirely the trigger's own `where`
      clause; this action applies none itself.
      """

      pagination keyset?: true
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
      here — each of those resources declares its own reference back to
      its parent with `on_delete: :delete` in its `postgres.references`
      block (`Measure`/`ChordSegment` to `Tab`/`Measure` respectively,
      `Note`/`ChordSuggestion` similarly), so the database itself takes
      care of the whole cascade without additional code in this action.
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
      status is the side effect the `:analyze_chords` AshOban trigger
      (issue #20) watches for to enqueue `:run_chord_analysis`
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

    update :mark_analyzing do
      accept []
      require_atomic? false

      description """
      Internal-only `status: :analyzing` flip (issue #20). Called as its
      own, independently-committed `Ash.update!` from
      `Ponteio.Tablatures.Changes.RunChordAnalysis` — never from a
      LiveView, and never as part of `:run_chord_analysis`'s own changeset
      — see that change module's moduledoc for why the two need to be
      genuinely separate writes.
      """

      change set_attribute(:status, :analyzing)
    end

    update :run_chord_analysis do
      accept []
      require_atomic? false

      # Disables AshOban's own transaction+lock wrapping around this
      # action's invocation — required for `:mark_analyzing` (above) to
      # commit independently rather than nesting inside this action's own
      # transaction. See `Ponteio.Tablatures.Changes.RunChordAnalysis`'s
      # moduledoc and the `:analyze_chords` trigger's own comment.
      transaction? false

      description """
      Runs the chord-suggestion engine (`Ponteio.Chords`, issues #15-#17)
      over every measure of this tab and persists the result as
      `ChordSegment`/`ChordSuggestion` rows (issue #20, PRD §6.4 regra 6,
      §8; SDD §3.4). Triggered automatically by the `:analyze_chords`
      AshOban trigger above whenever `status` is `:draft` or `:analyzing`
      — never called directly from a LiveView. See
      `Ponteio.Tablatures.Changes.RunChordAnalysis` for the actual
      orchestration (status transitions, PubSub broadcasts, persistence).
      """

      change Ponteio.Tablatures.Changes.RunChordAnalysis
    end
  end

  policies do
    # AshOban's scheduler/worker (issue #20) has no end-user actor behind
    # it — it's a cron-driven background computation acting on `tab.id`
    # alone, not a request made on anyone's behalf. Without this bypass,
    # the `where`-filtered read the scheduler performs (and the
    # `:run_chord_analysis` call itself) would fall through to the
    # policies below with `actor: nil`, which the `:filter`-access-type
    # read policy would quietly turn into "matches nothing" — the trigger
    # would never find any tab to analyze. This is `ash_oban`'s own
    # documented fix for exactly that (see its "Authorizing actions"
    # guide) — every *internal* call `RunChordAnalysis` itself makes
    # (reading `Measure`/`Note`, writing `ChordSegment`/`ChordSuggestion`)
    # instead passes `authorize?: false` directly, so this bypass only
    # needs to cover `Tab`'s own actions.
    bypass AshOban.Checks.AshObanInteraction do
      authorize_if always()
    end

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
