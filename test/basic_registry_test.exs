defmodule Ragistry.BasicRegistryTest do
  use ExUnit.Case

  test "register, lookup and unregister operations" do
    name = :test_registry
    {:ok, _pid} = Ragistry.start_link(name: name)

    # Test registration
    assert :ok = Ragistry.Machine.register(name, "key1", "value1")
    assert :ok = Ragistry.Machine.register(name, "key2", "value2")

    # Test lookups
    self = self()
    assert [{^self, "value1"}] = Ragistry.Machine.lookup(name, "key1")
    assert [{^self, "value2"}] = Ragistry.Machine.lookup(name, "key2")
    assert [] = Ragistry.Machine.lookup(name, "non_existent_key")

    # Test unregistration
    assert :ok = Ragistry.Machine.unregister(name, "key1")
    assert [] = Ragistry.Machine.lookup(name, "key1")
    assert [{^self, "value2"}] = Ragistry.Machine.lookup(name, "key2")
  end

  test "process exit removes registration" do
    name = :test_registry_exit
    {:ok, _pid} = Ragistry.start_link(name: name)

    task =
      Task.async(fn ->
        Ragistry.Machine.register(name, "key1", "value1")
        Process.sleep(100)
      end)

    # Wait for registration
    Process.sleep(10)
    pid = task.pid
    assert [{^pid, "value1"}] = Ragistry.Machine.lookup(name, "key1")

    # Let the task finish and check registration is gone
    Task.await(task)
    Process.sleep(10)
    assert [] = Ragistry.Machine.lookup(name, "key1")
  end

  test "via tuple registration" do
    name = TestRegistryVia
    {:ok, _pid} = Ragistry.start_link(name: name)

    # Start a GenServer using the registry for registration
    {:ok, pid} =
      Agent.start_link(
        fn -> 0 end,
        name: {:via, Ragistry.Machine, {name, "my_counter"}}
      )

    assert [{^pid, _}] = Ragistry.Machine.lookup(name, "my_counter")
  end

  test "duplicate registration returns error" do
    name = :test_registry2
    {:ok, _pid} = Ragistry.start_link(name: name)

    assert :ok = Ragistry.Machine.register(name, "key1", "value1")
    assert {:error, :already_registered} = Ragistry.Machine.register(name, "key1", "value1")
  end
end
