# Ragistry

A work-in-progress distributed process registry system built on top of the [Ra](https://github.com/rabbitmq/ra) implementation of Raft.

## Usage

```elixir
# Start the registry
{:ok, _pid} = Ragistry.start_link(name: :my_registry)

# Register a key-value pair
:ok = Ragistry.register(:my_registry, "key1", "value1")

# Look up a registration
[{pid, "value1"}] = Ragistry.lookup(:my_registry, "key1")

# Unregister a key
:ok = Ragistry.unregister(:my_registry, "key1")
```

Ragistry works across a cluster of nodes:

```
# Start registry on each node in the cluster
Node1> Ragistry.start_link(name: :distributed_registry)
Node2> Ragistry.start_link(name: :distributed_registry)

# Registration on one node is visible to all nodes
Node1> {:ok, pid} = Agent.start_link(
  fn -> "state" end,
  name: {:via, Ragistry, {:distributed_registry, "shared_key", "value"}}
)

# Look up from any node
Node2> [{pid, "value"}] = Ragistry.lookup(:distributed_registry, "shared_key")
```
