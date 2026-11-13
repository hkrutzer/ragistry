defmodule Ragistry.RegistryPropTest do
  use ExUnit.Case
  use ExUnitProperties
  alias Ragistry.Test.RegistryScenario, as: Scenario

  @keys [:a, :b, :c]
  @registrants [:alice, :bob, :carol]

  # Commands mirror function calls: {operation, arguments}. The :as wrapper
  # selects the calling process; {:pid, name} resolves a PID argument.
  defp command_generator(mode) do
    key = member_of(@keys)
    registrant = member_of(@registrants)
    pid = map(registrant, &{:pid, &1})

    shared = [
      as(registrant, command(:register, [key, value_generator()])),
      command(:lookup, [key]),
      as(registrant, command(:unregister, [key])),
      command(:dispatch, [key]),
      command(:dispatch_mfa, [key]),
      command(:count),
      command(:keys, [pid]),
      command(:values, [key, pid]),
      command(:put_meta, [key, value_generator()]),
      command(:meta, [key]),
      command(:delete_meta, [key]),
      match_command(member_of([:match, :count_match]), key),
      as(registrant, match_command(constant(:unregister_match), key)),
      select_command()
    ]

    case mode do
      :unique ->
        one_of([
          as(registrant, command(:update_value, [key, map(value_generator(), &{:set, &1})]))
          | shared
        ])

      :duplicate ->
        one_of(shared)
    end
  end

  defp value_generator do
    one_of([
      integer(),
      boolean(),
      constant(nil),
      binary(max_length: 12),
      list_of(integer(), max_length: 4),
      map(integer(), &{:score, &1}),
      map(integer(), &%{score: &1})
    ])
  end

  defp command(operation, arguments \\ []) do
    map(fixed_list(arguments), &{operation, &1})
  end

  defp as(registrant, command), do: tuple({constant(:as), registrant, command})

  defp match_command(operation, key) do
    arguments =
      one_of([
        constant({:_, []}),
        map(integer(), &{&1, []}),
        map(integer(), &{:"$1", [{:>, :"$1", &1}]}),
        map(integer(), &{{:score, :"$1"}, [{:>, :"$1", &1}]})
      ])

    gen all(operation <- operation, key <- key, {pattern, guards} <- arguments) do
      {operation, [key, pattern, guards]}
    end
  end

  defp select_command do
    guards =
      one_of([
        constant([]),
        map(integer(), &[{:"=:=", :"$3", &1}]),
        map(integer(), &[{:>, :"$3", &1}])
      ])

    gen all(
          operation <- member_of([:select, :count_select]),
          guards <- guards,
          projection <- member_of([{{:"$1", :"$2", :"$3"}}, :"$1", :"$3"]),
          count_result <- member_of([true, false, :"$3", {:is_integer, :"$3"}])
        ) do
      body = if operation == :select, do: [projection], else: [count_result]
      {operation, [[{{:"$1", :"$2", :"$3"}, guards, body}]]}
    end
  end

  defp execute(module, registry, {:as, registrant, command}, registrants) do
    Scenario.call(Map.fetch!(registrants, registrant), fn ->
      execute(module, registry, command, registrants)
    end)
  end

  defp execute(module, registry, {:update_value, [key, {:set, value}]}, _registrants) do
    module.update_value(registry, key, fn _ -> value end)
  end

  defp execute(module, registry, {operation, [key]}, _registrants)
       when operation in [:dispatch, :dispatch_mfa] do
    caller = self()
    ref = make_ref()

    callback =
      case operation do
        :dispatch -> fn entries -> deliver_dispatch(entries, caller, ref) end
        :dispatch_mfa -> {__MODULE__, :deliver_dispatch, [caller, ref]}
      end

    result = module.dispatch(registry, key, callback)

    # Default dispatch is synchronous. Ignore batch boundaries and ordering,
    # but retain duplicate entries when comparing callback observations.
    {result, ref |> collect_dispatch_entries([]) |> Enum.sort()}
  end

  defp execute(module, registry, {operation, arguments}, registrants) do
    arguments =
      Enum.map(arguments, fn
        {:pid, name} -> Map.fetch!(registrants, name)
        value -> value
      end)

    apply(module, operation, [registry | arguments])
  end

  # Public because dispatch/3 also accepts an MFA callback.
  def deliver_dispatch(entries, caller, ref) do
    assert is_list(entries) and entries != []
    send(caller, {ref, entries})
    :callback_result
  end

  defp collect_dispatch_entries(ref, entries) do
    receive do
      {^ref, batch} -> collect_dispatch_entries(ref, batch ++ entries)
    after
      0 -> entries
    end
  end

  defp assert_equivalent({:as, _registrant, command}, expected, actual),
    do: assert_equivalent(command, expected, actual)

  defp assert_equivalent({:register, _args}, {:ok, owner}, :ok) when is_pid(owner),
    do: :ok

  defp assert_equivalent({operation, _args}, expected, actual)
       when operation in [:keys, :select, :lookup, :match, :values] do
    assert Enum.sort(expected) == Enum.sort(actual)
  end

  defp assert_equivalent(_command, expected, actual), do: assert(expected == actual)

  defp run_commands(commands, mode) do
    Scenario.with_registries(mode, fn reference_registry, test_registry ->
      Scenario.with_workers(@registrants, fn registrants ->
        for command <- commands do
          expected = execute(Registry, reference_registry, command, registrants)
          actual = execute(Ragistry, test_registry, command, registrants)
          assert_equivalent(command, expected, actual)

          for key <- @keys do
            assert_equivalent(
              {:lookup, [key]},
              Registry.lookup(reference_registry, key),
              Ragistry.lookup(test_registry, key)
            )
          end
        end
      end)
    end)
  end

  property "registrants cannot modify each other's registrations" do
    check all(
            mode <- member_of([:unique, :duplicate]),
            owner <- member_of(@registrants),
            other <- member_of(@registrants -- [owner]),
            key <- member_of(@keys),
            value <- integer(),
            mutation <-
              member_of(
                [{:unregister, [key]}, {:unregister_match, [key, :_, []]}] ++
                  if(mode == :unique, do: [{:update_value, [key, {:set, value + 1}]}], else: [])
              )
          ) do
      # run_commands compares both the result and all registrations after each
      # command, so an unauthorized mutation cannot silently change the owner.
      run_commands(
        [
          {:as, owner, {:register, [key, value]}},
          {:as, other, mutation}
        ],
        mode
      )
    end
  end

  property "executes commands against Registry" do
    check all(
            mode <- member_of([:unique, :duplicate]),
            commands <- list_of(command_generator(mode))
          ) do
      run_commands(commands, mode)
    end
  end
end
