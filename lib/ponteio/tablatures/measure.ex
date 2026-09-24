defmodule Ponteio.Tablatures.Measure do
  @moduledoc """
  A "compasso" (bar) — the unit the chord-suggestion engine analyzes
  (PRD §6.3, §6.4; SDD §2.2).

  This resource is normatively specified by SDD §2.2 as part of the data
  model that issue #12 ("Inserir marcadores de compasso") builds its
  "+Adicionar compasso" / "quebrar compasso" UI on top of. It's introduced
  here, ahead of #12, purely as the technical prerequisite `Note`
  (`belongs_to :measure`) needs to exist and compile — `Note` is this
  issue's (#11) actual "Resource novo".

  Consistent with issues #11-#13's "Persistência" notes (each explicitly
  defers Measure/Note persistence to `upsert_measure_notes`, issue #14),
  no LiveView in this issue creates `Measure` rows against the database —
  the editor keeps compassos/notes as local `Phoenix.LiveView` assigns
  until #14's bulk save exists. The `:create`/`:read`/`:update`/`:destroy`
  actions and policy below exist so the resource is usable (and testable
  in isolation, and ready for #14 to call), not because anything calls
  them yet.
  """

  use Ash.Resource,
    otp_app: :ponteio,
    domain: Ponteio.Tablatures,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "measures"
    repo Ponteio.Repo

    references do
      # Deleting a `Tab` removes its whole `Measure`/`Note` tree at the
      # database level (`Tab`'s moduledoc/issue #9's stated expectation for
      # whichever dependent resource landed first).
      reference :tab, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:tab_id, :position]
    end

    update :update do
      primary? true
      accept [:position]
    end
  end

  policies do
    # Same shape as `Tab`'s policies (SDD §2.2, issue #10): a `Measure` is
    # only ever accessible/mutable through the `tab` it belongs to, and
    # that `tab` must belong to the actor. There is no `user_id` column
    # here to compare directly — `relates_to_actor_via/1` walks the
    # `[:tab, :user]` relationship path instead (issue #10's documented
    # pattern for dependent resources).
    #
    # This also covers `:create`: Ash resolves a relationship-based filter
    # check on a create action as a post-insert `SELECT ... WHERE pkey =
    # inserted.id AND <filter>` inside the same transaction, rolling back
    # if it doesn't match (Ash's documented "filter creates" behavior) — no
    # separate `relating_to_actor` check needed for the submitted `tab_id`.
    policy action_type([:create, :read, :update, :destroy]) do
      authorize_if relates_to_actor_via([:tab, :user])
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :position, :integer do
      allow_nil? false
      public? true
      constraints min: 1
      description "Ordering of this measure within the tablature (PRD §6.3, SDD §2.2)."
    end

    timestamps()
  end

  relationships do
    belongs_to :tab, Ponteio.Tablatures.Tab do
      allow_nil? false
    end

    has_many :notes, Ponteio.Tablatures.Note
  end
end
