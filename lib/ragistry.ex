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

  @doc """
  Starts a new registry instance.

  ## Options
    * `:name` - Required. The name to register the registry under.
  """
  defdelegate start_link(opts), to: Ragistry.Cluster

  @doc """
  Registers the current process in the registry under the given key with associated value.

  Returns `:ok` if successful, or `{:error, :already_registered}` if the key is already taken.
  """
  defdelegate register(name, key, value), to: Ragistry.Machine

  @doc """
  Looks up processes registered under the given key.

  Returns a list of tuples containing `{pid, value}` for all matching processes,
  or an empty list if no process is registered under the given key.
  """
  defdelegate lookup(name, key), to: Ragistry.Machine

  @doc """
  Unregisters the current process for the given key.

  Returns `:ok` if successful.
  """
  defdelegate unregister(name, key), to: Ragistry.Machine

  @doc false
  defdelegate whereis_name(via), to: Ragistry.Machine

  @doc false
  defdelegate register_name(via, pid), to: Ragistry.Machine
end
