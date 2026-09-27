defmodule Ponteio.Tablatures do
  @moduledoc """
  Tablatures, their measures and notes. Measures and notes are always looked up
  through their parent (`get_measure(tab_id, id)`, `get_note(measure_id, id)`),
  so an id sent by the browser can only reach rows of that parent.
  """

  use Ash.Domain, otp_app: :ponteio

  resources do
    resource Ponteio.Tablatures.Tab do
      define :list_tabs, action: :list
      define :get_tab, action: :read, get_by: [:id]
      define :create_tab, action: :create, args: [:title]
      define :destroy_tab, action: :destroy
    end

    resource Ponteio.Tablatures.Measure do
      define :list_measures, action: :for_tab, args: [:tab_id]
      define :get_measure, action: :get_in_tab, args: [:tab_id, :id]
      define :add_measure, action: :create, args: [:tab_id]
      define :add_notes, action: :add_notes, args: [:notes]
      define :destroy_measure, action: :destroy
    end

    resource Ponteio.Tablatures.Note do
      define :get_note, action: :get_in_measure, args: [:measure_id, :id]
      define :destroy_note, action: :destroy
    end
  end
end
