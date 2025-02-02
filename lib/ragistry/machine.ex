defmodule Ragistry.Machine do
  @behaviour :ra_machine

  @type state :: %{
          entries: %{term() => [{pid(), term()}]},
          type: :unique | :duplicate,
          meta: %{term() => term()}
        }

  @impl true
  def init(%{type: type}) when type in [:unique, :duplicate] do
    %{entries: %{}, type: type, meta: %{}}
  end

  def count(name) do
    server = server_id(name)
    {:ok, count, _} = :ra.process_command(server, {:count})
    count
  end

  def count_match(name, key, pattern, guards \\ []) do
    server = server_id(name)
    {:ok, count, _} = :ra.process_command(server, {:count_match, key, pattern, guards})
    count
  end

  def count_select(name, spec) do
    server = server_id(name)
    {:ok, count, _} = :ra.process_command(server, {:count_select, spec})
    count
  end

  def delete_meta(name, key) do
    server = server_id(name)
    {:ok, :ok, _} = :ra.process_command(server, {:delete_meta, key})
    :ok
  end

  def dispatch(name, key, mfa_or_fun) do
    lookup(name, key) |> apply_mfa_or_fun(mfa_or_fun)
    :ok
  end

  def keys(name, pid) do
    server = server_id(name)
    {:ok, keys, _} = :ra.process_command(server, {:keys, pid})
    keys
  end

  def match(name, key, pattern, guards \\ []) do
    server = server_id(name)
    {:ok, matches, _} = :ra.process_command(server, {:match, key, pattern, guards})
    matches
  end

  def meta(name, key) do
    server = server_id(name)
    {:ok, value, _} = :ra.process_command(server, {:get_meta, key})
    value
  end

  def put_meta(name, key, value) do
    server = server_id(name)
    {:ok, :ok, _} = :ra.process_command(server, {:put_meta, key, value})
    :ok
  end

  def select(name, spec) do
    server = server_id(name)
    {:ok, results, _} = :ra.process_command(server, {:select, spec})
    results
  end

  def unregister_match(name, key, pattern, guards \\ []) do
    server = server_id(name)
    {:ok, :ok, _} = :ra.process_command(server, {:unregister_match, key, pattern, guards, self()})
    :ok
  end

  def update_value(name, key, value) do
    server = server_id(name)
    {:ok, result, _} = :ra.process_command(server, {:update_value, key, value, self()})
    result
  end

  def values(name, key, pid) do
    server = server_id(name)
    {:ok, values, _} = :ra.process_command(server, {:values, key, pid})
    values
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
      error -> raise error
    end
  end

  # Used by Ragistry.Machine.register/3
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

  # Used by Ragistry.Machine.register/3
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

  # Used by Ragistry.Machine.unregister/2
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

  # Used by Ragistry.Machine.lookup/2
  def apply(_meta, {:lookup, key}, state) do
    result = Map.get(state.entries, key, [])
    {state, result, []}
  end

  # Used internally for process monitoring
  def apply(_meta, {:down, pid, _reason}, state) do
    # Filter out entries for the downed process
    new_entries =
      Map.new(state.entries, fn {key, entries} ->
        {key, Enum.reject(entries, fn {p, _} -> p == pid end)}
      end)

    new_state = %{state | entries: new_entries}
    {new_state, :ok, []}
  end

  # Used by Ragistry.Machine.count/1
  def apply(_meta, {:count}, state) do
    count = map_size(state.entries)
    {state, count, []}
  end

  # Used by Ragistry.Machine.count_match/4
  def apply(_meta, {:count_match, key, pattern, guards}, state) do
    match_spec = [{{:_, pattern}, guards, [~c"$_"]}]
    compiled_ms = :ets.match_spec_compile(match_spec)

    count =
      state.entries
      |> Map.get(key, [])
      |> Enum.count(fn entry ->
        case :ets.match_spec_run([entry], compiled_ms) do
          [_] -> true
          [] -> false
        end
      end)

    {state, count, []}
  end

  # Used by Ragistry.Machine.count_select/2
  def apply(_meta, {:count_select, spec}, state) do
    compiled_ms = :ets.match_spec_compile(spec)

    count =
      state.entries
      |> Enum.flat_map(fn {key, entries} ->
        entries
        |> Enum.map(fn {pid, value} -> {key, pid, value} end)
        |> :ets.match_spec_run(compiled_ms)
      end)
      |> length()

    {state, count, []}
  end

  # Used by Ragistry.Machine.delete_meta/2
  def apply(_meta, {:delete_meta, key}, state) do
    new_state = update_in(state.meta, &Map.delete(&1, key))
    {new_state, :ok, []}
  end

  # Used by Ragistry.Machine.keys/2
  def apply(_meta, {:keys, pid}, state) do
    keys =
      state.entries
      |> Enum.filter(fn {_k, entries} -> Enum.any?(entries, fn {p, _} -> p == pid end) end)
      |> Enum.map(fn {k, _} -> k end)

    {state, keys, []}
  end

  # Used by Ragistry.Machine.match/4
  def apply(_meta, {:match, key, pattern, guards}, state) do
    # Create match spec that matches on the {pid, value} structure
    match_spec = [{{:_, pattern}, guards, [~c"$_"]}]
    compiled_ms = :ets.match_spec_compile(match_spec)

    matches =
      state.entries
      |> Map.get(key, [])
      |> Enum.filter(fn entry ->
        case :ets.match_spec_run([entry], compiled_ms) do
          [_] -> true
          [] -> false
        end
      end)

    {state, matches, []}
  end

  # Used by Ragistry.Machine.meta/2
  def apply(_meta, {:get_meta, key}, state) do
    value = Map.get(state.meta, key)
    {state, value, []}
  end

  # Used by Ragistry.Machine.put_meta/3
  def apply(_meta, {:put_meta, key, value}, state) do
    new_state = put_in(state.meta[key], value)
    {new_state, :ok, []}
  end

  # Used by Ragistry.Machine.select/2
  def apply(_meta, {:select, spec}, state) do
    compiled_ms = :ets.match_spec_compile(spec)

    results =
      state.entries
      |> Enum.flat_map(fn {key, entries} ->
        entries
        |> Enum.map(fn {pid, value} -> {key, pid, value} end)
        |> :ets.match_spec_run(compiled_ms)
      end)

    {state, results, []}
  end

  # Used by Ragistry.Machine.values/3
  def apply(_meta, {:values, key, pid}, state) do
    values =
      state.entries
      |> Map.get(key, [])
      |> Enum.filter(fn {p, _} -> p == pid end)
      |> Enum.map(fn {_, value} -> value end)

    {state, values, []}
  end

  # Used by Ragistry.Machine.update_value/3
  def apply(_meta, {:update_value, key, callback, pid}, %{type: :unique} = state) do
    case Map.get(state.entries, key) do
      [{^pid, old_value}] ->
        new_value = callback.(old_value)
        new_state = put_in(state.entries[key], [{pid, new_value}])
        {new_state, {new_value, old_value}}

      _ ->
        {state, :error, []}
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

  # Internal functions
  defp apply_mfa_or_fun([], _) do
    :ok
  end

  defp apply_mfa_or_fun(xs, {m, f, a}) do
    Kernel.apply(m, f, [xs | a])
  end

  defp apply_mfa_or_fun(xs, fun) do
    fun.(xs)
  end

  defp server_id(registry_name) do
    server_id(registry_name, node())
  end

  defp server_id(registry_name, node) when is_atom(node) do
    (Atom.to_string(node) <> "_" <> Atom.to_string(registry_name))
    |> String.to_atom()
  end
end
