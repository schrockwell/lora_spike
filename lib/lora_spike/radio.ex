defmodule LoraSpike.Radio do
  use GenServer

  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def ping(timeout \\ 1000) do
    GenServer.cast(__MODULE__, {:start_ping, self(), timeout})
  end

  @impl GenServer
  def init(_) do
    #
    # Couple notes:
    #   - /dev/spidev0.1 is the SPI device on the Raspberry Pi 2 B+
    #   - The :encoding option requires the fork of the :lora dependency at
    #     https://github.com/schrockwell/Elixir-LoRa/tree/add-encoding
    #
    {:ok, lora_pid} = LoRa.start_link(spi: "spidev0.1", encoding: :term)

    LoRa.begin(lora_pid, 915.0e6)

    Logger.info("LoRa radio initialized")

    {:ok,
     %{
       lora_pid: lora_pid,
       pong_to_pid: nil
     }}
  end

  @impl GenServer
  def handle_info({:lora, %{packet: {:ping, %{from: from}}}}, state) do
    packet = {:pong, %{from: this_device_id(), to: from}}
    LoRa.send(state.lora_pid, packet)

    {:noreply, state}
  end

  def handle_info({:lora, %{packet: {:pong, %{to: to, from: from}} = packet}}, state) do
    if to == this_device_id() && state.pong_to_pid do
      Logger.debug("Pong received from #{from}")
      send(state.pong_to_pid, packet)
    end

    {:noreply, state}
  end

  def handle_info({:lora, info}, state) do
    Logger.info(inspect(info), label: "LoRa")

    {:noreply, state}
  end

  def handle_info(:stop_ping, state) do
    {:noreply, %{state | pong_to_pid: nil}}
  end

  @impl GenServer
  def handle_cast({:start_ping, sender, ping_timeout}, state) do
    packet = {:ping, %{from: this_device_id()}}
    LoRa.send(state.lora_pid, packet)

    if state.pong_to_pid do
      {:noreply, state}
    else
      Process.send_after(self(), :stop_ping, ping_timeout)
      {:noreply, %{state | pong_to_pid: sender}}
    end
  end

  defp this_device_id, do: Nerves.Runtime.serial_number()
end
