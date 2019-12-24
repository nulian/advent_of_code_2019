defmodule IntOpEngine do
  @moduledoc false

  use GenServer, restart: :temporary

  require Logger

  defmodule State do
    defmodule Flags do
      defstruct param_1_mode: 0, param_2_mode: 0, param_3_mode: 0
    end

    defstruct command_list: [],
              lookup_map: %{},
              current_index: 0,
              argument_flags: nil,
              input_request: false,
              input_list: [],
              last_output: [],
              output_pid: nil,
              result_pid: nil,
              relative_base: 0

    def new(arguments) do
      Map.merge(%State{argument_flags: %Flags{}}, arguments)
    end

    def reset_flags(%State{} = state) do
      %{state | argument_flags: %Flags{}}
    end
  end

  def get_data_list(filename) do
    "data/#{filename}.data"
    |> File.read!()
    |> String.split(",")
    |> Enum.map(&String.to_integer/1)
  end

  def start_link({:command_list, list}, arguments) do
    {name, arguments} = Keyword.pop(arguments, :name)

    options =
      if name do
        [name: name]
      else
        []
      end

    GenServer.start_link(__MODULE__, Enum.into([{:command_list, list} | arguments], %{}), options)
  end

  @impl true
  def init(state) do
    {:ok, State.new(state), {:continue, :enhance_state}}
  end

  @impl true
  def handle_continue(:enhance_state, %{command_list: command_list} = state) do
    lookup_map = Enum.into(Enum.with_index(command_list), %{}, fn {value, int} -> {int, value} end)

    {:noreply, %State{state | lookup_map: lookup_map}}
  end

  @impl true
  def handle_info(:timeout, %State{last_output: [t, x, y | rest]} = state) do
    #    Logger.error(t)

    pid =
      if t == 255 do
        GenServer.whereis(:nat)
      else
        GenServer.whereis(String.to_atom("cpu#{t}"))
      end

    GenServer.cast(pid, {:set_input, x})
    GenServer.cast(pid, {:set_input, y})
    {:noreply, %State{state | last_output: rest}, 0}
  end

  @impl true
  def handle_info(:timeout, state) do
    parse_list(State.reset_flags(state))
  end

  @impl true
  def handle_call({:set_output_pid, pid}, _, state) when is_pid(pid) do
    {:reply, :ok, %{state | output_pid: pid}}
  end

  @impl true
  def handle_call({:set_output_pid, _pid}, _, state) do
    {:reply, :invalid_pid, state}
  end

  def handle_call(:start_run, _, state) do
    {:reply, :ok, state, 0}
  end

  @impl true
  def handle_cast({:set_input, input}, %{command_list: [3, address | rest], input_request: true} = state) do
    state = %{state | current_index: state.current_index + 2}

    {updated_map, rest} = update_value(state, rest, address, input, state.argument_flags.param_1_mode)

    updated_state = %{
      state
      | command_list: rest,
        lookup_map: updated_map,
        current_index: state.current_index,
        input_request: false
    }

    {:noreply, updated_state, 0}
  end

  @impl true
  def handle_cast({:set_input, input}, state) do
    #    Logger.info("received input #{inspect(self())} #{input}")
    {:noreply, %{state | input_list: state.input_list ++ [input]}, 0}
  end

  defp parse_list(%{command_list: [1, a, b, value | rest]} = state) do
    val_a = value_lookup(state, a, state.argument_flags.param_1_mode)
    val_b = value_lookup(state, b, state.argument_flags.param_2_mode)

    state = %{state | current_index: state.current_index + 4}

    {updated_map, rest} = update_value(state, rest, value, val_a + val_b, state.argument_flags.param_3_mode)

    {:noreply, %{state | command_list: rest, lookup_map: updated_map}, 0}
  end

  defp parse_list(%{command_list: [2, a, b, value | rest]} = state) do
    val_a = value_lookup(state, a, state.argument_flags.param_1_mode)
    val_b = value_lookup(state, b, state.argument_flags.param_2_mode)

    state = %{state | current_index: state.current_index + 4}

    {updated_map, rest} = update_value(state, rest, value, val_a * val_b, state.argument_flags.param_3_mode)

    {:noreply, %{state | command_list: rest, lookup_map: updated_map}, 0}
  end

  defp parse_list(%{command_list: [3, address | rest], input_list: [input | remaining_input]} = state) do
    state = %{state | current_index: state.current_index + 2}

    {updated_map, rest} = update_value(state, rest, address, input, state.argument_flags.param_1_mode)

    updated_state = %{
      state
      | command_list: rest,
        lookup_map: updated_map,
        input_list: remaining_input
    }

    {:noreply, updated_state, 0}
  end

  defp parse_list(%{command_list: [3, _address | _rest]} = state) do
    {:noreply, %{state | input_list: state.input_list ++ [-1]}, 500}
  end

  #  defp parse_list(%{command_list: [3, _address | _rest]} = state) do
  #    Logger.info("Waiting for input:")
  #
  #    {:noreply, %{state | input_request: true}, :hibernate}
  #  end

  # Puts
  defp parse_list(%{command_list: [4, address | rest], output_pid: output_pid} = state) when is_pid(output_pid) do
    value = value_lookup(state, address, state.argument_flags.param_1_mode)
    #    Logger.info(value)
    GenServer.cast(output_pid, {:set_input, value})
    {:noreply, %{state | command_list: rest, last_output: value, current_index: state.current_index + 2}, 0}
  end

  defp parse_list(%{command_list: [4, address | rest]} = state) do
    value = value_lookup(state, address, state.argument_flags.param_1_mode)
    #    Logger.info(value)

    {:noreply,
     %{state | command_list: rest, last_output: state.last_output ++ [value], current_index: state.current_index + 2},
     0}
  end

  defp parse_list(%{command_list: [key, x, value | rest]} = state) when key in [5, 6] do
    val_x = value_lookup(state, x, state.argument_flags.param_1_mode)
    new_index = value_lookup(state, value, state.argument_flags.param_2_mode)

    case val_x do
      x when (key == 5 and x == 0) or (key == 6 and x != 0) ->
        {:noreply, %{state | command_list: rest, current_index: state.current_index + 3}, 0}

      _ ->
        reset_rest =
          state.lookup_map
          |> Enum.sort_by(&elem(&1, 0))
          |> Enum.split(new_index)
          |> elem(1)
          |> Enum.map(&elem(&1, 1))

        {:noreply, %{state | command_list: reset_rest, current_index: new_index}, 0}
    end
  end

  defp parse_list(%{command_list: [key, x, y, set_value | rest]} = state) when key in [7, 8] do
    val_x = value_lookup(state, x, state.argument_flags.param_1_mode)
    val_y = value_lookup(state, y, state.argument_flags.param_2_mode)

    comparison_value =
      case {val_x, val_y} do
        {x, y} when (x < y and key == 7) or (x == y and key == 8) -> 1
        {_x, _y} -> 0
      end

    state = %{state | current_index: state.current_index + 4}

    {updated_map, rest} = update_value(state, rest, set_value, comparison_value, state.argument_flags.param_3_mode)

    {:noreply, %{state | command_list: rest, lookup_map: updated_map}, 0}
  end

  defp parse_list(%{command_list: [9, adjustment | rest]} = state) do
    adjust_value = value_lookup(state, adjustment, state.argument_flags.param_1_mode)

    {:noreply,
     %{
       state
       | command_list: rest,
         relative_base: state.relative_base + adjust_value,
         current_index: state.current_index + 2
     }, 0}
  end

  defp parse_list(%{command_list: [99 | _], result_pid: result_pid} = state) when is_pid(result_pid) do
    Logger.info("result send")
    send(result_pid, {:result, state.last_output})
    {:stop, :normal, state}
  end

  defp parse_list(%{command_list: [99 | _]} = state) do
    Logger.info("Finished with: " <> inspect(state, limit: :infinity, printable_limit: :infinity))
    {:stop, :normal, state}
  end

  defp parse_list(%{command_list: [opcode | rest]} = state) when opcode > 99 do
    [_, e, d, c, b, a, _] =
      opcode
      |> Integer.to_string()
      |> String.pad_leading(5, "0")
      |> String.to_charlist()
      |> Enum.reverse()
      |> List.to_string()
      |> String.split("")

    function = String.to_integer(d <> e)
    param_1_mode = String.to_integer(c)
    param_2_mode = String.to_integer(b)
    param_3_mode = String.to_integer(a)

    parse_list(%{
      state
      | command_list: [function | rest],
        argument_flags: %{
          state.argument_flags
          | param_1_mode: param_1_mode,
            param_2_mode: param_2_mode,
            param_3_mode: param_3_mode
        }
    })
  end

  defp update_value(%State{} = state, rest_list, key, value, 0) do
    updated_map = Map.put(state.lookup_map, key, value)
    rest_index = key - state.current_index

    rest_list =
      if rest_index >= 0 do
        List.replace_at(rest_list, rest_index, value)
      else
        rest_list
      end

    {updated_map, rest_list}
  end

  defp update_value(%State{} = state, rest_list, relative_key_value, value, 2) do
    relative_key = state.relative_base + relative_key_value
    updated_map = Map.put(state.lookup_map, relative_key, value)
    rest_index = relative_key - state.current_index

    rest_list =
      if rest_index >= 0 do
        List.replace_at(rest_list, rest_index, value)
      else
        rest_list
      end

    {updated_map, rest_list}
  end

  defp value_lookup(%State{lookup_map: lookup_map}, key, 0) do
    Map.get(lookup_map, key, 0)
  end

  defp value_lookup(_, key, 1) do
    key
  end

  defp value_lookup(%State{lookup_map: lookup_map, relative_base: relative_base}, key, 2) do
    Map.get(lookup_map, relative_base + key, 0)
  end
end
