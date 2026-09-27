# Seeds tablatures from text files in priv/repo/seeds/tabs/*.txt (see the
# README.md there for the format). Runs on every `docker compose up`, so it
# only creates tabs whose title does not exist yet.
#
#     mix run priv/repo/seeds.exs

alias Ponteio.Tablatures

existing_titles = MapSet.new(Tablatures.list_tabs!(), & &1.title)

"seeds/tabs/*.txt"
|> Path.expand(__DIR__)
|> Path.wildcard()
|> Enum.sort()
|> Enum.each(fn path ->
  lines =
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))

  {title_lines, measures} = Enum.split_with(lines, &String.starts_with?(&1, "title:"))

  title =
    case title_lines do
      ["title:" <> title] -> String.trim(title)
      _ -> raise "#{path}: expected exactly one `title:` line"
    end

  if MapSet.member?(existing_titles, title) do
    IO.puts("Seed: \"#{title}\" already exists, skipping.")
  else
    tab = Tablatures.create_tab!(title)

    Enum.each(measures, fn notes ->
      tab.id |> Tablatures.add_measure!() |> Tablatures.add_notes!(notes)
    end)

    IO.puts("Seed: created \"#{title}\" with #{length(measures)} measures.")
  end
end)
