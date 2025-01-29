defmodule Ragistry.Machine do
  @moduledoc false

  @behaviour :ra_machine

  @type state :: %{
          entries: %{term() => [{pid(), term()}]},
          type: :unique | :duplicate
        }

  @impl true
  def init(%{type: type}) when type in [:unique, :duplicate] do
    %{entries: %{}, type: type}
  end

  @impl true
  def apply(_meta, {:register, key, pid, value}, %{type: :unique} = state) do
    case Map.get(state.entries, key) do
      nil ->
        state = put_in(state.entries[key], [{pid, value}])
        {state, :ok, [{:monitor, :process, pid}]}

      _other ->
        {state, {:error, :already_registered}, []}
    end
  end

  def apply(_meta, {:register, key, pid, value}, %{type: :duplicate} = state) do
    effects =
      if Map.get(state.entries, key) == nil do
        [{:monitor, :process, pid}]
      else
        []
      end

    state =
      update_in(state.entries[key], fn entries ->
        [{pid, value} | entries || []]
      end)

    {state, :ok, effects}
  end

  def apply(_meta, {:unregister, key, pid}, state) do
    case Map.get(state.entries, key) do
      nil ->
        {state, :ok, []}

      entries ->
        new_entries = Enum.reject(entries, fn {p, _} -> p == pid end)
        new_state = put_in(state.entries[key], new_entries)
        {new_state, :ok, []}
    end
  end

  def apply(_meta, {:lookup, key}, state) do
    result = Map.get(state.entries, key, [])
    {state, result, []}
  end

  def apply(_meta, {:down, pid, _reason}, state) do
    # Filter out entries for the downed process
    new_entries =
      Map.new(state.entries, fn {key, entries} ->
        {key, Enum.reject(entries, fn {p, _} -> p == pid end)}
      end)

    new_state = %{state | entries: new_entries}
    {new_state, :ok, []}
  end

  def register(name, key, value) do
    server = {server_id(name), node()}

    case :ra.process_command(server, {:register, key, self(), value}) do
      {:ok, :ok, _} -> :ok
      {:ok, {:error, reason}, _} -> {:error, reason}
      error -> error
    end
  end

  def unregister(name, key) do
    server = server_id(name)
    :ra.process_command(server, {:unregister, key, self()})
    :ok
  end

  def lookup(name, key) do
    server = server_id(name)

    case :ra.process_command(server, {:lookup, key}) do
      {:ok, entries, _} -> entries
      error -> error
    end
  end

  # Functions used for "via" registration
  def whereis_name({registry, key}) do
    case lookup(registry, key) do
      [{pid, _value}] -> pid
      _ -> :undefined
    end
  end

  def whereis_name({registry, key, _value}), do: whereis_name({registry, key})

  def register_name({registry, key}, pid), do: register_name({registry, key, nil}, pid)

  def register_name({registry, key, value}, _pid) do
    case register(registry, key, value) do
      :ok -> :yes
      _ -> :no
    end
  end

  def unregister_name({registry, key, _value}) do
    unregister(registry, key)
  end

  defp server_id(registry_name) do
    server_id(registry_name, node())
  end

  defp server_id(registry_name, node) when is_atom(node) do
    (Atom.to_string(node) <> "_" <> Atom.to_string(registry_name))
    |> String.to_atom()
  end
end
