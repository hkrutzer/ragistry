defmodule Ragistry.Cluster do
  use GenServer
  require Logger

  @pg_group :cluster_managers

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def child_spec(opts) do
    %{
      id: opts[:name] || __MODULE__,
      start: {Ragistry, :start_link, [opts]},
      type: :supervisor
    }
  end

  def init(opts) do
    name = opts[:name]
    type = Keyword.get(opts, :type, :unique)
    cluster_name = name
    machine = {:module, Ragistry.Machine, %{type: type}}
    pg_scope = name

    :pg.start_link(pg_scope)

    # TODO See if there is a better way
    Process.sleep(500)

    case :pg.get_members(pg_scope, @pg_group) -- [self()] do
      [] ->
        # We're first - start the cluster
        Logger.debug("Starting new Ra cluster #{inspect(cluster_name)}")

        {:ok, _, _} =
          :ra.start_cluster(:default, cluster_name, machine, [{server_id(name), node()}])

      members ->
        # Join existing cluster through any member
        [existing_member | _] = members -- [self()]
        existing_node = node(existing_member)
        Logger.debug("Joining existing cluster through #{inspect(existing_member)}")

        :ra.start_server(
          :default,
          cluster_name,
          {server_id(name), node()},
          machine,
          [{server_id(name, existing_node), existing_node}]
        )

        :ra.add_member({server_id(name, existing_node), existing_node}, {server_id(name), node()})
    end

    :ok = :pg.join(pg_scope, @pg_group, self())
    :pg.get_members(pg_scope, @pg_group)

    {:ok, %{name: opts[:name]}}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    # TODO Handle member down - could trigger re-election/recovery
    {:noreply, state}
  end

  defp server_id(registry_name) do
    server_id(registry_name, node())
  end

  defp server_id(registry_name, node) when is_atom(node) do
    (Atom.to_string(node) <> "_" <> Atom.to_string(registry_name))
    |> String.to_atom()
  end
end
