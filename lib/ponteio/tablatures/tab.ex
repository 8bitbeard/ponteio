defmodule Ponteio.Tablatures.Tab do
  @moduledoc """
  A tablature's metadata: title, artist, and capo position, plus the status
  the UI uses to know when chord analysis is pending (per PRD §6.2, SDD
  §2.2).

  Issue #6 ("Criar nova tablatura") implemented `:create`. This issue (#7,
  "Listar minhas tablaturas") adds `:read`, plus the read policy that keeps
  the listing scoped to its owner — anticipating issue #10 ("Isolamento de
  tablaturas por usuário"), which will apply the same
  `actor(:user).id == user_id` shape to `update`/`destroy` once those
  actions exist (issues #8/#9).
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
  end

  policies do
    # Only an authenticated actor may create a tablature — it is always
    # related to that actor via `relate_actor(:user)` above, so there is no
    # "create on behalf of someone else" case to guard against here.
    policy action(:create) do
      authorize_if actor_present()
    end

    # A tablature is only ever readable by its owner (SDD §2.2, issue #10)
    # — implemented here (ahead of #10) so `:read`/`list_tabs_for_user`
    # never expose another user's tablatures (issue #7's stated dependency
    # on #10).
    policy action_type(:read) do
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
  end
end
