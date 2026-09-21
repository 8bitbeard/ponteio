defmodule Ponteio.Chords.ChordShape do
  @moduledoc """
  Catalog entry for a chord "shape": a curated fret-and-string pattern that
  can be applied at a given `base_fret` on the neck to produce a specific
  chord (per SDD §2.3).

  This is read-only catalog data seeded by the application
  (`priv/repo/seeds.exs`) — end users never create, update, or delete
  `ChordShape` records, so no `Ash.Policy.Authorizer` is configured here.
  """

  use Ash.Resource,
    otp_app: :ponteio,
    domain: Ponteio.Chords,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "chord_shapes"
    repo Ponteio.Repo
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :slug,
        :name,
        :quality,
        :root_string,
        :movable,
        :min_base_fret,
        :max_base_fret,
        :relative_frets
      ]

      upsert? true
      upsert_identity :unique_slug

      upsert_fields [
        :name,
        :quality,
        :root_string,
        :movable,
        :min_base_fret,
        :max_base_fret,
        :relative_frets
      ]
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :slug, :string do
      allow_nil? false
      public? true

      description "Stable unique identifier used by the seed for idempotent upserts (ex.: \"c-major-open\")."
    end

    attribute :name, :string do
      allow_nil? false
      public? true

      description """
      Human-readable label for the shape's quality (ex.: Maior, Menor, 7, Sus4,
      Dim, Aug), per SDD §2.3. The full chord name (ex.: Mi Maior) is computed
      at runtime from root_string + base_fret + standard tuning, not stored here.
      """
    end

    attribute :quality, :atom do
      allow_nil? false
      public? true

      constraints one_of: [
                    :major,
                    :minor,
                    :dominant_seventh,
                    :sus2,
                    :sus4,
                    :diminished,
                    :augmented
                  ]

      description "Chord quality, used to name the resulting chord."
    end

    attribute :root_string, :integer do
      allow_nil? false
      public? true
      constraints min: 1, max: 6
      description "Which string (1 = high E .. 6 = low E) carries the root note used for naming."
    end

    attribute :relative_frets, {:array, :integer} do
      allow_nil? false
      public? true
      constraints items: [], min_length: 6, max_length: 6, nil_items?: true

      description "Six positions (one per string, high E to low E), each an offset relative to " <>
                    "base_fret, or nil when the string is muted / not part of the shape."
    end

    attribute :movable, :boolean do
      allow_nil? false
      public? true
      default false
      description "true = barre/movable shape, false = open-position shape."
    end

    attribute :min_base_fret, :integer do
      allow_nil? false
      public? true
      constraints min: 0
      default 0
      description "Lowest fret this shape can be applied at (0 for open chords)."
    end

    attribute :max_base_fret, :integer do
      allow_nil? false
      public? true
      constraints min: 0
      default 0
      description "Highest fret this shape can be applied at (0 for open chords)."
    end

    timestamps()
  end

  identities do
    identity :unique_slug, [:slug]
  end
end
