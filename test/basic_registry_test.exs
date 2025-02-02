defmodule Ragistry.BasicRegistryTest do
  use ExUnit.Case

  test "register, lookup and unregister operations" do
    name = :test_registry
    {:ok, _pid} = Ragistry.start_link(name: name)

    # Test registration
    assert :ok == Ragistry.register(name, "key1", "value1")
    assert :ok == Ragistry.register(name, "key2", "value2")

    # Test lookups
    self = self()
    assert [{self, "value1"}] == Ragistry.lookup(name, "key1")
    assert [{self, "value2"}] == Ragistry.lookup(name, "key2")
    assert [] = Ragistry.lookup(name, "non_existent_key")

    # Test unregistration
    assert :ok == Ragistry.unregister(name, "key1")
    assert [] == Ragistry.lookup(name, "key1")
    assert [{self, "value2"}] == Ragistry.lookup(name, "key2")
  end

  test "process exit removes registration" do
    name = :test_registry_exit
    {:ok, _pid} = Ragistry.start_link(name: name)

    task =
      Task.async(fn ->
        Ragistry.register(name, "key1", "value1")
        Process.sleep(100)
      end)

    # Wait for registration
    Process.sleep(10)
    pid = task.pid
    assert [{pid, "value1"}] == Ragistry.lookup(name, "key1")

    # Let the task finish and check registration is gone
    Task.await(task)
    Process.sleep(10)
    assert [] = Ragistry.lookup(name, "key1")
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

    [{^pid, _}] = Ragistry.lookup(name, "my_counter")
  end

  test "duplicate registration returns error" do
    name = :test_registry2
    {:ok, _pid} = Ragistry.start_link(name: name)

    assert :ok == Ragistry.register(name, "key1", "value1")
    assert {:error, :already_registered} == Ragistry.register(name, "key1", "value1")
  end

  test "count returns number of registrations" do
    name = :test_registry_count
    {:ok, _pid} = Ragistry.start_link(name: name)

    assert 0 == Ragistry.count(name)

    Ragistry.register(name, "key1", "value1")
    Ragistry.register(name, "key2", "value2")

    assert 2 == Ragistry.count(name)
  end

  test "count_match returns number of matches" do
    name = :test_registry_count_match
    {:ok, _pid} = Ragistry.start_link(name: name, type: :duplicate)

    # Register some test data with the same key
    value1 = {1, :atom, 1}
    value2 = {1, :atom, 2}
    value3 = {2, :atom, 3}

    :ok = Ragistry.register(name, "shared_key", value1)
    :ok = Ragistry.register(name, "shared_key", value2)
    :ok = Ragistry.register(name, "other_key", value3)

    # Test pattern matching on specific keys
    assert 2 == Ragistry.count_match(name, "shared_key", {1, :atom, :_})
    assert 0 == Ragistry.count_match(name, "shared_key", {2, :atom, :_})
    assert 1 == Ragistry.count_match(name, "other_key", {2, :atom, :_})

    # Test with guards
    assert 1 == Ragistry.count_match(name, "shared_key", {:_, :_, :"$1"}, [{:>, :"$1", 1}])
    assert 0 == Ragistry.count_match(name, "shared_key", {:_, :_, :"$1"}, [{:>, :"$1", 2}])
  end

  test "count_select returns number of matches for complex patterns" do
    name = :test_registry_count_select
    {:ok, _pid} = Ragistry.start_link(name: name, type: :duplicate)

    # Register test data
    :ok = Ragistry.register(name, "key1", {1, :atom, 1})
    :ok = Ragistry.register(name, "key1", {2, :atom, 2})
    :ok = Ragistry.register(name, "key2", {1, :atom, 3})

    # Count all entries
    assert 3 == Ragistry.count_select(name, [{{:_, :_, :_}, [], [true]}])

    # Count entries with specific key
    assert 2 ==
             Ragistry.count_select(name, [
               {{"key1", :_, :_}, [], [true]}
             ])

    # Count entries matching value pattern and guard
    assert 2 ==
             Ragistry.count_select(name, [
               {{:_, :_, {:"$1", :atom, :_}}, [{:<, :"$1", 2}], [true]}
             ])
  end

  test "match supports patterns and guards" do
    name = :test_registry_match
    {:ok, _pid} = Ragistry.start_link(name: name)

    value = {1, :atom, 2}
    :ok = Ragistry.register(name, "hello", value)

    assert [{self(), value}] == Ragistry.match(name, "hello", {1, :_, :_})
    assert [] == Ragistry.match(name, "hello", {2, :_, :_})
    assert [{self(), value}] == Ragistry.match(name, "hello", {:_, :atom, :_})

    # With guards
    assert [{self(), value}] ==
             Ragistry.match(name, "hello", {:_, :_, :"$1"}, [{:>, :"$1", 1}])

    assert [] ==
             Ragistry.match(name, "hello", {:_, :_, :"$1"}, [{:>, :"$1", 2}])
  end

  test "keys returns all keys for a pid" do
    name = :test_registry_keys
    {:ok, _pid} = Ragistry.start_link(name: name)

    :ok = Ragistry.register(name, "key1", "value1")
    :ok = Ragistry.register(name, "key2", "value2")

    assert ["key1", "key2"] == Ragistry.keys(name, self()) |> Enum.sort()
  end

  test "values returns all values for a key and pid" do
    name = :test_registry_values
    {:ok, _pid} = Ragistry.start_link(name: name)

    :ok = Ragistry.register(name, "key1", "value1")

    assert ["value1"] == Ragistry.values(name, "key1", self())
    assert [] == Ragistry.values(name, "nonexistent", self())
  end

  test "select supports match specifications" do
    name = :test_registry_select
    {:ok, _pid} = Ragistry.start_link(name: name)

    :ok = Ragistry.register(name, "hello", {1, :atom, 1})
    :ok = Ragistry.register(name, "world", {2, :atom, 2})

    # Select all entries
    result = Ragistry.select(name, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}])
    assert length(result) == 2

    # Select with condition
    assert [{"world", self(), {2, :atom, 2}}] ==
             Ragistry.select(name, [
               {{"world", :"$2", {:"$3", :atom, :"$4"}}, [],
                [{{"world", :"$2", {{:"$3", :atom, :"$4"}}}}]}
             ])
  end

  test "update_value modifies existing registration" do
    name = :test_registry_update
    {:ok, _pid} = Ragistry.start_link(name: name)

    :ok = Ragistry.register(name, "counter", 1)
    assert {2, 1} = Ragistry.update_value(name, "counter", &(&1 + 1))

    [{_pid, value}] = Ragistry.lookup(name, "counter")
    assert value == 2
  end

  test "meta operations work correctly" do
    name = :test_registry_meta
    {:ok, _pid} = Ragistry.start_link(name: name)

    # Test putting and getting meta
    assert :ok == Ragistry.put_meta(name, :counter, 1)
    assert 1 == Ragistry.meta(name, :counter)

    # Test updating existing meta
    assert :ok == Ragistry.put_meta(name, :counter, 2)
    assert 2 == Ragistry.meta(name, :counter)

    # Test getting non-existent meta
    assert nil == Ragistry.meta(name, :nonexistent)

    # Test deleting meta
    assert :ok == Ragistry.delete_meta(name, :counter)
    assert nil == Ragistry.meta(name, :counter)

    # Test deleting non-existent meta
    assert :ok == Ragistry.delete_meta(name, :nonexistent)
  end

  test "meta supports different value types" do
    name = :test_registry_meta_types
    {:ok, _pid} = Ragistry.start_link(name: name)

    test_values = [
      {:atom_key, :atom_value},
      {:string_key, "string value"},
      {:number_key, 12345},
      {:tuple_key, {1, 2, 3}},
      {:map_key, %{a: 1, b: 2}},
      {:list_key, [1, 2, 3]}
    ]

    for {key, value} <- test_values do
      assert :ok == Ragistry.put_meta(name, key, value)
      assert value == Ragistry.meta(name, key)
    end
  end

  test "dispatch executes function for matching processes" do
    name = :test_registry_dispatch
    {:ok, _pid} = Ragistry.start_link(name: name, type: :duplicate)

    # Test dispatch with no registered processes
    fun = fn _ -> raise "should not be called" end
    assert :ok == Ragistry.dispatch(name, "key1", fun)

    # Register some test processes
    :ok = Ragistry.register(name, "key1", :value1)
    :ok = Ragistry.register(name, "key1", :value2)
    :ok = Ragistry.register(name, "key2", :value3)

    # Test dispatch with matching process
    test_pid = self()

    dispatch_fun = fn entries ->
      assert test_pid == self()
      for {pid, value} <- entries, do: send(pid, {:dispatch, value})
    end

    assert Ragistry.dispatch(name, "key1", dispatch_fun)

    assert_received {:dispatch, :value1}
    assert_received {:dispatch, :value2}
    refute_received {:dispatch, :value3}

    fun = fn entries ->
      assert test_pid == self()
      for {pid, value} <- entries, do: send(pid, {:dispatch, value})
    end

    assert Ragistry.dispatch(name, "key2", fun)

    refute_received {:dispatch, :value1}
    refute_received {:dispatch, :value2}
    assert_received {:dispatch, :value3}
  end
end
