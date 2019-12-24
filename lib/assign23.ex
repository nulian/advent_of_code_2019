defmodule Assign23 do
  @moduledoc false

  defmodule Pipeline do
    use DynamicSupervisor

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

  defmodule Nat do
    use GenServer
    require Logger

    def start_link(args) do
      GenServer.start_link(__MODULE__, [], name: :nat)
    end

    @impl true
    def init([]) do
      {:ok, %{input_list: []}, 0}
    end

    @impl true
    def handle_info(:timeout, %{input_list: [y, x | rest]} = state) do
      result =
        Enum.map(0..49, fn i ->
          pid = GenServer.whereis(String.to_atom("cpu#{i}"))
          %{input_list: list} = :sys.get_state(pid)

          list == []
        end)
        |> Enum.uniq()
        |> length

      if result == 1 do
        Process.sleep(500)
        Logger.info("send #{y}")
        GenServer.cast(:cpu0, {:set_input, x})
        GenServer.cast(:cpu0, {:set_input, y})
        {:noreply, %{input_list: []}, :hibernate}
      else
        {:noreply, state, 500}
      end
    end

    @impl true
    def handle_info(:timeout, state) do
      {:noreply, state, :hibernate}
    end

    @impl true
    def handle_cast({:set_input, input}, state) do
      #      Logger.info("received input #{inspect(self())} #{input}")
      {:noreply, %{state | input_list: [input | state.input_list]}, 0}
    end
  end

  def assignment do
    {:ok, super_pid} = Pipeline.start_link(command_list: IntOpEngine.get_data_list("assign23"))

    Nat.start_link([])

    Enum.each(0..49, fn i ->
      Pipeline.start_child(input_list: [i], name: String.to_atom("cpu#{i}"))
    end)

    Enum.each(0..49, fn i ->
      pid = GenServer.whereis(String.to_atom("cpu#{i}"))
      GenServer.call(pid, :start_run)
    end)
  end
end
