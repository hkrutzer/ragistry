defmodule Ragistry.RegistryTest do
  use ExUnitCluster.Case, async: true

  test "basic registration works", %{cluster: cluster} do
    # Start two nodes in our cluster
    node1 = ExUnitCluster.start_node(cluster)
    node2 = ExUnitCluster.start_node(cluster)

    # Start the registry on both nodes
    ExUnitCluster.call(cluster, node1, Ragistry, :start_link, [[name: :my_registry]])
    ExUnitCluster.call(cluster, node2, Ragistry, :start_link, [[name: :my_registry]])

    # Start an Agent with via registration
    {:ok, agent_pid} =
      ExUnitCluster.call(cluster, node1, Agent, :start_link, [
        fn -> "initial_state" end,
        [name: {:via, Ragistry, {:my_registry, "test_key", "value1"}}]
      ])

    # Verify registration is visible from both nodes
    lookup1 =
      ExUnitCluster.call(cluster, node1, Ragistry, :lookup, [:my_registry, "test_key"])

    lookup2 =
      ExUnitCluster.call(cluster, node2, Ragistry, :lookup, [:my_registry, "test_key"])

    assert [{^agent_pid, "value1"}] = lookup1
    assert lookup1 == lookup2
  end

  test "handles process death", %{cluster: cluster} do
    node1 = ExUnitCluster.start_node(cluster)
    node2 = ExUnitCluster.start_node(cluster)

    ExUnitCluster.call(cluster, node1, Ragistry, :start_link, [[name: :my_registry]])
    ExUnitCluster.call(cluster, node2, Ragistry, :start_link, [[name: :my_registry]])

    test_pid =
      ExUnitCluster.in_cluster(cluster, node1,
        do:
          spawn(fn ->
            Ragistry.register(:my_registry, :test_proc, 1)

            receive do
              :stop -> :ok
            end
          end)
      )

    # Verify registration is visible from the other node
    [{^test_pid, _}] =
      ExUnitCluster.call(cluster, node2, Ragistry, :lookup, [:my_registry, :test_proc])

    ExUnitCluster.call(cluster, node1, Process, :exit, [test_pid, :kill])

    # Verify process death is detected on the other node
    [] = ExUnitCluster.call(cluster, node2, Ragistry, :lookup, [:my_registry, :test_proc])
  end

  test "registration visible to newly joined node", %{cluster: cluster} do
    # Start first node and registry
    node1 = ExUnitCluster.start_node(cluster)
    ExUnitCluster.call(cluster, node1, Ragistry, :start_link, [[name: :my_registry]])

    # Start and register an Agent on first node
    {:ok, agent_pid} =
      ExUnitCluster.call(cluster, node1, Agent, :start_link, [
        fn -> "initial_state" end,
        [name: {:via, Ragistry, {:my_registry, "test_key", "value1"}}]
      ])

    # Verify registration on first node
    lookup1 =
      ExUnitCluster.call(cluster, node1, Ragistry, :lookup, [:my_registry, "test_key"])

    assert [{^agent_pid, "value1"}] = lookup1

    # Start second node and registry after registration
    node2 = ExUnitCluster.start_node(cluster)
    ExUnitCluster.call(cluster, node2, Ragistry, :start_link, [[name: :my_registry]])

    # Verify registration is visible on newly joined node
    lookup2 =
      ExUnitCluster.call(cluster, node2, Ragistry, :lookup, [:my_registry, "test_key"])

    assert lookup1 == lookup2
  end
end
