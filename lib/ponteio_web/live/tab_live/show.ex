defmodule PonteioWeb.TabLive.Show do
  use PonteioWeb, :live_view

  alias Ponteio.Chords.HandPosition
  alias Ponteio.Chords.MeasureAnalyzer
  alias Ponteio.Tablatures
  alias Ponteio.Tablatures.NoteNotation

  @max_alternatives 20
  @measure_load [:notes, :hand_positions, :chord_positions]
  @modes [
    hand: {"Posição de mão", "Dedos podem ser levantados para a corda soar solta."},
    chord: {"Formato de acorde", "O formato completo do acorde fica pressionado."}
  ]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    tab = Tablatures.get_tab!(id)

    {:ok,
     socket
     |> assign(tab: tab, page_title: tab.title, mode: :hand, modes: @modes)
     |> assign(focused_measure_id: nil, note_errors: %{})
     |> stream(:measures, Tablatures.list_measures!(tab.id))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@tab.title}
        <:subtitle>
          Notas no formato corda + casa, separadas por espaço: <code>E3 D0 G2 e2</code>
          (<code>E</code>
          = Mi grave, <code>e</code>
          = Mi agudo). Clique numa nota para removê-la.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/tabs"}>Voltar</.button>
        </:actions>
      </.header>

      <div id="mode-picker" class="mb-4 flex flex-wrap items-center gap-3">
        <div role="tablist" class="tabs tabs-box">
          <button
            :for={{mode, {label, _description}} <- @modes}
            id={"mode-#{mode}"}
            type="button"
            role="tab"
            phx-click="set_mode"
            phx-value-mode={mode}
            class={["tab", @mode == mode && "tab-active"]}
          >
            {label}
          </button>
        </div>
        <p class="text-sm text-base-content/70">{@modes[@mode] |> elem(1)}</p>
      </div>

      <div id="measures" phx-update="stream" class="space-y-4">
        <p id="measures-empty" class="hidden only:block text-sm text-base-content/60">
          Nenhum compasso ainda.
        </p>
        <section
          :for={{dom_id, measure} <- @streams.measures}
          id={dom_id}
          class="rounded-box border border-base-300 p-4"
        >
          <div class="flex items-center justify-between">
            <h2 class="font-semibold">Compasso {measure.position + 1}</h2>
            <button
              id={"delete-measure-#{measure.id}"}
              type="button"
              phx-click="delete_measure"
              phx-value-id={measure.id}
              data-confirm="Excluir este compasso e suas notas?"
              class="btn btn-ghost btn-sm"
            >
              <.icon name="hero-trash" class="size-4" /> Excluir compasso
            </button>
          </div>

          <div id={"notes-#{measure.id}"} class="flex flex-wrap gap-1 my-2">
            <span :if={measure.notes == []} class="text-sm text-base-content/60">Sem notas.</span>
            <button
              :for={note <- measure.notes}
              id={"note-#{note.id}"}
              type="button"
              phx-click="delete_note"
              phx-value-measure-id={measure.id}
              phx-value-note-id={note.id}
              title="Remover nota"
              class="badge badge-outline gap-1 font-mono cursor-pointer hover:badge-error"
            >
              {NoteNotation.format(note)}<.icon name="hero-x-mark" class="size-3" />
            </button>
          </div>

          <.form
            for={to_form(%{})}
            id={"add-notes-#{measure.id}-#{length(measure.notes)}"}
            phx-submit="add_notes"
            class="flex items-start gap-2"
          >
            <input type="hidden" name="measure_id" value={measure.id} />
            <div class="flex-1">
              <.input
                id={"notes-input-#{measure.id}"}
                name="notes"
                value=""
                placeholder="E3 D0 G2 A0"
                autocomplete="off"
                class="w-full input font-mono"
                phx-mounted={@focused_measure_id == measure.id && JS.focus()}
              />
            </div>
            <.button id={"add-notes-button-#{measure.id}"}>Adicionar notas</.button>
          </.form>
          <p :if={@note_errors[measure.id]} class="text-sm text-error">{@note_errors[measure.id]}</p>

          <.analysis
            measure_id={measure.id}
            combinations={
              if @mode == :hand, do: measure.hand_positions, else: measure.chord_positions
            }
          />
        </section>
      </div>

      <.button id="add-measure" phx-click="add_measure" class="btn btn-primary mt-4">
        <.icon name="hero-plus" class="size-4" /> Adicionar compasso
      </.button>
    </Layouts.app>
    """
  end

  attr :measure_id, :string, required: true
  attr :combinations, :list, required: true

  defp analysis(assigns) do
    ~H"""
    <div :if={@combinations != []} id={"analysis-#{@measure_id}"} class="mt-3 space-y-2">
      <div
        :for={{combination, index} <- Enum.with_index(@combinations, 1)}
        class="rounded-box bg-base-200 p-3"
      >
        <p class="text-xs text-base-content/70 mb-2">
          Combinação {index} de {length(@combinations)} · {length(combination.segments)} posições de mão · complexidade {combination.total_complexity}
        </p>
        <ol class="space-y-2">
          <.segment :for={segment <- combination.segments} segment={segment} />
        </ol>
      </div>
    </div>
    """
  end

  attr :segment, MeasureAnalyzer.Segment, required: true

  defp segment(assigns) do
    assigns =
      assign(assigns,
        best: List.first(assigns.segment.candidates),
        alternatives: assigns.segment.candidates |> Enum.drop(1) |> Enum.take(@max_alternatives),
        hidden_count: max(length(assigns.segment.candidates) - 1 - @max_alternatives, 0)
      )

    ~H"""
    <li class="text-sm">
      <span class="font-mono">{Enum.map_join(@segment.notes, " ", &NoteNotation.format/1)}</span>
      <span :if={@best}>
        → <strong>{HandPosition.chord_name(@best)}</strong>
        <span class="font-mono">{HandPosition.diagram(@best)}</span>
        <span class="text-base-content/60">(complexidade {@best.complexity})</span>
      </span>
      <span :if={!@best} class="text-warning">→ nenhuma posição toca esta nota</span>
      <details :if={@alternatives != []} class="ml-4">
        <summary class="cursor-pointer text-xs text-base-content/70">
          {length(@segment.candidates) - 1} alternativas
        </summary>
        <ul class="text-xs font-mono">
          <li :for={candidate <- @alternatives}>
            {HandPosition.chord_name(candidate)} {HandPosition.diagram(candidate)} (complexidade {candidate.complexity})
          </li>
          <li :if={@hidden_count > 0} class="text-base-content/60">… e mais {@hidden_count}</li>
        </ul>
      </details>
    </li>
    """
  end

  @impl true
  def handle_event("set_mode", %{"mode" => mode}, socket) when mode in ["hand", "chord"] do
    {:noreply,
     socket
     |> assign(mode: String.to_existing_atom(mode), focused_measure_id: nil)
     |> stream(:measures, Tablatures.list_measures!(socket.assigns.tab.id), reset: true)}
  end

  def handle_event("add_measure", _params, socket) do
    measure = Tablatures.add_measure!(socket.assigns.tab.id, load: @measure_load)

    {:noreply,
     socket
     |> assign(:focused_measure_id, measure.id)
     |> stream_insert(:measures, measure)}
  end

  def handle_event("add_notes", %{"measure_id" => id, "notes" => text}, socket) do
    measure = Tablatures.get_measure!(socket.assigns.tab.id, id)

    case Tablatures.add_notes(measure, text, load: @measure_load) do
      {:ok, measure} ->
        {:noreply,
         socket
         |> assign(:focused_measure_id, measure.id)
         |> update(:note_errors, &Map.delete(&1, measure.id))
         |> stream_insert(:measures, measure)}

      {:error, error} ->
        {:noreply,
         socket
         |> update(:note_errors, &Map.put(&1, measure.id, error_message(error)))
         |> stream_insert(:measures, measure)}
    end
  end

  def handle_event("delete_note", %{"measure-id" => measure_id, "note-id" => note_id}, socket) do
    tab_id = socket.assigns.tab.id
    measure = Tablatures.get_measure!(tab_id, measure_id)
    measure.id |> Tablatures.get_note!(note_id) |> Tablatures.destroy_note!()

    {:noreply,
     socket
     |> assign(:focused_measure_id, nil)
     |> stream_insert(:measures, Tablatures.get_measure!(tab_id, measure.id))}
  end

  def handle_event("delete_measure", %{"id" => id}, socket) do
    tab_id = socket.assigns.tab.id
    tab_id |> Tablatures.get_measure!(id) |> Tablatures.destroy_measure!()

    {:noreply,
     socket
     |> assign(:focused_measure_id, nil)
     |> stream(:measures, Tablatures.list_measures!(tab_id), reset: true)}
  end

  defp error_message(%{errors: errors}) do
    Enum.map_join(errors, "; ", fn
      %{field: :notes, message: message} when is_binary(message) -> message
      error -> Exception.message(error)
    end)
  end
end
