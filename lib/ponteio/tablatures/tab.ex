defmodule Ponteio.Tablatures.Tab do
  @moduledoc """
  A tablature's metadata: title, artist, and capo position, plus the status
  the UI uses to know when chord analysis is pending (per PRD §6.2, SDD
  §2.2).

  This foundational issue (#6, "Criar nova tablatura") only implements the
  `:create` action — reading, updating, and deleting a tablature (and the
  per-user isolation policy that scopes those actions to their owner) are
  added by the later `epic:tablatures` issues (#7-#10).
  """

  use Ash.Resource,
    otp_app: :ponteio,
    domain: Ponteio.Tablatures,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

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
  end

  policies do
    # Only an authenticated actor may create a tablature — it is always
    # related to that actor via `relate_actor(:user)` above, so there is no
    # "create on behalf of someone else" case to guard against here.
    policy action(:create) do
      authorize_if actor_present()
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
