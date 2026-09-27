defmodule Ponteio.Tablatures.Note do
  @moduledoc """
  One note of a measure. `string` (1 = high e .. 6 = low E), `fret` (0 = open)
  and `position` (playing order) are the fields `Ponteio.Chords.MeasureAnalyzer`
  reads, so notes go into the analyzer as they are.
  """

  use Ash.Resource,
    otp_app: :ponteio,
    domain: Ponteio.Tablatures,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "notes"
    repo Ponteio.Repo

    references do
      reference :measure, on_delete: :delete
    end

    custom_indexes do
      index [:measure_id, :position]
    end
  end

  actions do
    defaults [:read, :destroy]

    read :get_in_measure do
      get? true
      argument :measure_id, :uuid, allow_nil?: false
      argument :id, :uuid, allow_nil?: false
      filter expr(measure_id == ^arg(:measure_id) and id == ^arg(:id))
    end

    create :create do
      accept [:measure_id, :position, :string, :fret]
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :position, :integer do
      allow_nil? false
      public? true
      constraints min: 0
    end

    attribute :string, :integer do
      allow_nil? false
      public? true
      constraints min: 1, max: 6
    end

    attribute :fret, :integer do
      allow_nil? false
      public? true
      constraints min: 0, max: 24
    end

    timestamps()
  end

  relationships do
    belongs_to :measure, Ponteio.Tablatures.Measure do
      allow_nil? false
      public? true
    end
  end
end
