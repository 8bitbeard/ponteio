defmodule Ponteio.Tablatures.Tab do
  use Ash.Resource,
    otp_app: :ponteio,
    domain: Ponteio.Tablatures,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "tabs"
    repo Ponteio.Repo
  end

  actions do
    defaults [:read, :destroy]

    read :list do
      prepare build(sort: [inserted_at: :desc, id: :desc])
    end

    create :create do
      accept [:title]
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
      constraints max_length: 200
    end

    timestamps()
  end

  relationships do
    has_many :measures, Ponteio.Tablatures.Measure
  end

  aggregates do
    max :last_measure_position, :measures, :position
  end
end
