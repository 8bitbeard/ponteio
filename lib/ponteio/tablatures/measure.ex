defmodule Ponteio.Tablatures.Measure do
  use Ash.Resource,
    otp_app: :ponteio,
    domain: Ponteio.Tablatures,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  alias Ponteio.Chords.MeasureAnalyzer

  postgres do
    table "measures"
    repo Ponteio.Repo

    references do
      reference :tab, on_delete: :delete
    end

    custom_indexes do
      index [:tab_id, :position]
    end
  end

  actions do
    defaults [:read]

    read :for_tab do
      argument :tab_id, :uuid, allow_nil?: false
      filter expr(tab_id == ^arg(:tab_id))
      prepare build(sort: [position: :asc], load: [:notes, :hand_positions, :chord_positions])
    end

    read :get_in_tab do
      get? true
      argument :tab_id, :uuid, allow_nil?: false
      argument :id, :uuid, allow_nil?: false
      filter expr(tab_id == ^arg(:tab_id) and id == ^arg(:id))
      prepare build(load: [:notes, :hand_positions, :chord_positions])
    end

    create :create do
      description "Appends a measure to the end of its tab."
      accept [:tab_id]
      change Ponteio.Tablatures.Changes.AppendMeasure
    end

    update :add_notes do
      description "Appends notes written as `E3 D0 e2` to the end of the measure."
      require_atomic? false
      argument :notes, :string, allow_nil?: false
      change Ponteio.Tablatures.Changes.AddNotes
    end

    update :shift_back do
      description "Moves a measure one position earlier, used to close the gap of a deleted one."
      change atomic_update(:position, expr(position - 1))
    end

    destroy :destroy do
      description "Deletes a measure and renumbers the ones after it."
      primary? true
      require_atomic? false

      change after_action(fn _changeset, measure, _context ->
               __MODULE__
               |> Ash.Query.filter(tab_id == ^measure.tab_id and position > ^measure.position)
               |> Ash.bulk_update!(:shift_back, %{}, strategy: :atomic)

               {:ok, measure}
             end)
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :position, :integer do
      allow_nil? false
      public? true
      constraints min: 0
    end

    timestamps()
  end

  relationships do
    belongs_to :tab, Ponteio.Tablatures.Tab do
      allow_nil? false
      public? true
    end

    has_many :notes, Ponteio.Tablatures.Note do
      sort position: :asc
    end
  end

  calculations do
    calculate :hand_positions,
              {:array, :struct},
              {Ponteio.Tablatures.Calculations.HandPositions, mode: :hand} do
      description "Hand positions where fingers may lift and let their strings ring open (the default view)."
      constraints items: [instance_of: MeasureAnalyzer.Combination]
    end

    calculate :chord_positions,
              {:array, :struct},
              {Ponteio.Tablatures.Calculations.HandPositions, mode: :chord} do
      description "Hand positions holding each chord shape in full."
      constraints items: [instance_of: MeasureAnalyzer.Combination]
    end
  end

  aggregates do
    max :last_note_position, :notes, :position
  end
end
