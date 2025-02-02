defmodule Ragistry do
  @moduledoc """
  A distributed process registry for Elixir applications.

  Ragistry provides a simple interface for process registration and lookup across a cluster
  of Elixir nodes. It supports:

  - Process registration with associated metadata
  - Process lookup across nodes
  - Automatic process deregistration on termination
  - Via tuple registration for use with GenServers and other OTP behaviors

  ## Examples

      # Start the registry
      {:ok, _pid} = Ragistry.start_link(name: :my_registry)

      # Register a process
      Ragistry.register(:my_registry, "my_key", "my_value")

      # Look up a process
      [{pid, value}] = Ragistry.lookup(:my_registry, "my_key")

      # Use with GenServer via tuple
      {:ok, pid} = GenServer.start_link(MyServer, [],
        name: {:via, Ragistry, {:my_registry, "server_key", "metadata"}})

  The registry automatically handles process monitoring and cleanup when registered
  processes terminate, maintaining consistency across the cluster.
  """

  defdelegate start_link(opts), to: Ragistry.Cluster
  defdelegate child_spec(opts), to: Ragistry.Cluster
  defdelegate register(name, key, value), to: Ragistry.Machine
  defdelegate lookup(name, key), to: Ragistry.Machine
  defdelegate unregister(name, key), to: Ragistry.Machine
  defdelegate count(name), to: Ragistry.Machine
  defdelegate count_match(name, key, pattern, guards \\ []), to: Ragistry.Machine
  defdelegate count_select(name, spec), to: Ragistry.Machine
  defdelegate dispatch(name, key, mfa), to: Ragistry.Machine
  defdelegate keys(name, pid), to: Ragistry.Machine
  defdelegate match(name, key, pattern, guards \\ []), to: Ragistry.Machine
  defdelegate meta(name, key), to: Ragistry.Machine
  defdelegate put_meta(name, key, value), to: Ragistry.Machine
  defdelegate delete_meta(name, key), to: Ragistry.Machine
  defdelegate select(name, spec), to: Ragistry.Machine
  defdelegate unregister_match(name, key, pattern, guards \\ []), to: Ragistry.Machine
  defdelegate update_value(name, key, value), to: Ragistry.Machine
  defdelegate values(name, key, pid), to: Ragistry.Machine

  @doc false
  defdelegate whereis_name(via), to: Ragistry.Machine

  @doc false
  defdelegate register_name(via, pid), to: Ragistry.Machine
end
