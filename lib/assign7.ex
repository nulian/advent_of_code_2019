defmodule Assign7 do
  @moduledoc false

  defmodule Pipeline do
    use DynamicSupervisor, max_restarts: 10000

    def start_link(init_arg) do
      DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
    end

    def start_child(arguments) do
      spec = {IntOpEngine, arguments}
      DynamicSupervisor.start_child(__MODULE__, spec)
    end

    @impl true
    def init(init_arg) do
      DynamicSupervisor.init(strategy: :one_for_one, extra_arguments: init_arg)
    end
  end

  def assignment() do
    Pipeline.start_link(command_list: list()) |> IO.inspect()

    Enum.reduce(permutations([5, 6, 7, 8, 9]), [], fn [a, b, c, d, e] = config, acc ->
      {:ok, pid5} = Pipeline.start_child(input_list: [e], result_pid: self())
      {:ok, pid4} = Pipeline.start_child(input_list: [d], output_pid: pid5)
      {:ok, pid3} = Pipeline.start_child(input_list: [c], output_pid: pid4)
      {:ok, pid2} = Pipeline.start_child(input_list: [b], output_pid: pid3)
      {:ok, pid1} = Pipeline.start_child(input_list: [a, 0], output_pid: pid2)

      :ok = GenServer.call(pid5, {:set_output_pid, pid1})

      Pipeline
      |> DynamicSupervisor.which_children()
      |> Enum.reverse()
      |> Enum.each(fn {_, pid, _, _} ->
        IO.inspect(pid, label: "starting pid")
        :ok = GenServer.call(pid, :start_run)
      end)

      value =
        receive do
          {:result, value} -> value
        end

      [{config, value} | acc]
    end)

    #
    #
    #
  end

  def list do
    "data/assign7.data"
    |> File.read!()
    |> String.split(",")
    |> Enum.map(&String.to_integer/1)
  end

  #  def calculate_pipeline([a, b, c, d, e] = config, value) do
  #    value = parse(a, value)
  #    value = parse(b, value)
  #    value = parse(c, value)
  #    value = parse(d, value)
  #    result = parse(e, value)
  #
  #    result
  #  end

  def permutations([]), do: [[]]

  def permutations(list),
    do: for(elem <- list, rest <- permutations(list -- [elem]), do: [elem | rest])
end
