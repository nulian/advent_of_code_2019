defmodule IntOpEngine do
  @moduledoc false

  use GenServer

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
              last_output: nil,
              output_pid: nil

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

  @impl true
  def init(program_list) do
    {:ok, State.new(%{command_list: program_list}), {:continue, :enhance_state}}
  end

  @impl true
  def handle_continue(:enhance_state, %{command_list: command_list} = state) do
    lookup_map = Enum.into(Enum.with_index(command_list), %{}, fn {value, int} -> {int, value} end)

    {:noreply, %State{state | lookup_map: lookup_map}, 0}
  end

  @impl true
  def handle_info(:timeout, state) do
    parse_list(State.reset_flags(state))
  end

  @impl true
  def handle_cast({:set_input, input}, %{command_list: [3, address | rest], input_request: true} = state) do
    {updated_map, rest, new_index} = update_value(state.lookup_map, rest, state.current_index + 2, address, input)

    updated_state = %{
      state
      | command_list: rest,
        lookup_map: updated_map,
        current_index: new_index,
        input_request: false
    }

    {:noreply, updated_state, 0}
  end

  def handle_case({:set_input, _}, state) do
    Logger.warn("Invalid time for input.")
    {:noreply, state}
  end

  defp parse_list(%{command_list: [1, a, b, value | rest]} = state) do
    val_a = value_lookup(state.lookup_map, a, state.argument_flags.param_1_mode)
    val_b = value_lookup(state.lookup_map, b, state.argument_flags.param_2_mode)

    {updated_map, rest, new_index} = update_value(state.lookup_map, rest, state.current_index + 4, value, val_a + val_b)

    {:noreply, %{state | command_list: rest, lookup_map: updated_map, current_index: new_index}, 0}
  end

  defp parse_list(%{command_list: [2, a, b, value | rest]} = state) do
    val_a = value_lookup(state.lookup_map, a, state.argument_flags.param_1_mode)
    val_b = value_lookup(state.lookup_map, b, state.argument_flags.param_2_mode)

    {updated_map, rest, new_index} = update_value(state.lookup_map, rest, state.current_index + 4, value, val_a * val_b)

    {:noreply, %{state | command_list: rest, lookup_map: updated_map, current_index: new_index}, 0}
  end

  # Input
  #  def parse_list(
  #        [3, address | rest],
  #        %{input_list: [input | other_inputs]} = lookup_map,
  #        index,
  #        _flags
  #      ) do
  #    {updated_map, rest, new_index} = update_value(lookup_map, rest, index + 2, address, input)
  #    parse_list(rest, Map.put(updated_map, :input_list, other_inputs), new_index)
  #  end
  #
  #  def parse_list(
  #        [3, address | rest],
  #        %{input_list: _, output_list: head} = lookup_map,
  #        index,
  #        _flags
  #      ) do
  #    {updated_map, rest, new_index} = update_value(lookup_map, rest, index + 2, address, head)
  #    parse_list(rest, Map.put(updated_map, :input_list, head), new_index)
  #  end

  defp parse_list(%{command_list: [3, _address | _rest]} = state) do
    Logger.info("Waiting for inputt:")
    {:noreply, %{state | input_request: true}, :hibernate}
    #    {updated_map, rest, new_index} = update_value(state.lookup_map, rest, state.current_index + 2, address, input)
    #    parse_list(rest, updated_map, new_index)
  end

  # Puts
  defp parse_list(%{command_list: [4, address | rest]} = state) do
    value = value_lookup(state.lookup_map, address, state.argument_flags.param_1_mode)
    Logger.info(value)
    {:noreply, %{state | command_list: rest, last_output: value, current_index: state.current_index + 2}, 0}
  end

  defp parse_list(%{command_list: [key, x, value | rest]} = state) when key in [5, 6] do
    val_x = value_lookup(state.lookup_map, x, state.argument_flags.param_1_mode)
    new_index = value_lookup(state.lookup_map, value, state.argument_flags.param_2_mode)

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

  defp parse_list(%{command_list: [key, x, y, value | rest]} = state) when key in [7, 8] do
    val_x = value_lookup(state.lookup_map, x, state.argument_flags.param_1_mode)
    val_y = value_lookup(state.lookup_map, y, state.argument_flags.param_2_mode)

    comparison_value =
      case {val_x, val_y} do
        {x, y} when (x < y and key == 7) or (x == y and key == 8) -> 1
        {_x, _y} -> 0
      end

    {updated_map, rest, new_index} =
      update_value(state.lookup_map, rest, state.current_index + 4, value, comparison_value)

    {:noreply, %{state | command_list: rest, lookup_map: updated_map, current_index: new_index}, 0}
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

  defp update_value(lookup_map, rest_list, index, key, value) do
    updated_map = Map.put(lookup_map, key, value)
    rest_index = key - index

    rest_list =
      if rest_index >= 0 do
        List.replace_at(rest_list, key - index, value)
      else
        rest_list
      end

    {updated_map, rest_list, index}
  end

  defp value_lookup(map, key, 0) do
    Map.get(map, key)
  end

  defp value_lookup(_, key, 1) do
    key
  end
end
