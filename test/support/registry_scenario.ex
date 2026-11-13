defmodule Ragistry.Test.RegistryScenario do
  @moduledoc false
  import ExUnit.Assertions

  def with_registries(mode, fun) do
    reference = Ragistry.Test.ReferenceRegistry
    {:ok, pid} = Registry.start_link(keys: mode, name: reference)

    try do
      with_ragistry(mode, &fun.(reference, &1))
    after
      Supervisor.stop(pid)
    end
  end

  def with_ragistry(mode, fun) do
    name = Ragistry.Test.SubjectRegistry
    {:ok, manager} = Ragistry.start_link(name: name, keys: mode)

    try do
      fun.(name)
    after
      # Stop the manager before deleting the retained Ra state.
      GenServer.stop(manager)
      :ok = :ra.force_delete_server(:default, Ragistry.Server.id(name))
    end
  end

  def with_workers(names, fun) do
    workers =
      Map.new(names, fn name ->
        {:ok, pid} = Agent.start_link(fn -> nil end)
        {name, pid}
      end)

    try do
      fun.(workers)
    after
      # Workers must exit before the Registry partitions they link to.
      for pid <- Map.values(workers), Process.alive?(pid), do: stop_worker(pid, :normal)
    end
  end

  def call(pid, fun) do
    # Propagate failures to StreamData without crashing a linked worker.
    result =
      Agent.get(
        pid,
        fn _ ->
          try do
            {:ok, fun.()}
          catch
            kind, reason -> {:raised, kind, reason, __STACKTRACE__}
          end
        end,
        10_000
      )

    case result do
      {:ok, value} -> value
      {:raised, kind, reason, stacktrace} -> :erlang.raise(kind, reason, stacktrace)
    end
  end

  def stop_worker(pid, reason) do
    ref = Process.monitor(pid)
    Process.unlink(pid)

    case reason do
      :normal -> Agent.stop(pid)
      :kill -> Process.exit(pid, :kill)
    end

    assert_receive {:DOWN, ^ref, :process, ^pid, _}, 2_000
  end

  def entries(module, registry) do
    module.select(registry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}])
    |> Enum.sort()
  end

  def assert_eventually(fun, timeout \\ 2_000) do
    retry(fun, System.monotonic_time(:millisecond) + timeout)
  end

  defp retry(fun, deadline) do
    fun.()
  rescue
    error in ExUnit.AssertionError ->
      remaining = deadline - System.monotonic_time(:millisecond)

      if remaining <= 0 do
        reraise error, __STACKTRACE__
      else
        receive do
        after
          min(10, remaining) -> retry(fun, deadline)
        end
      end
  end
end
