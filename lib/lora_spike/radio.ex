defmodule LoraSpike.Radio do
  use GenServer

  require Logger

  alias LoraSpike.Packet

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def ping_async(timeout \\ 1000) do
    GenServer.cast(__MODULE__, {:start_ping_async, self(), timeout})
  end

  def ping(timeout \\ 1000) do
    GenServer.call(__MODULE__, {:start_ping_sync, timeout}, timeout + 1000)
  end

  def set_signal(bandwidth, spreading_factor) do
    GenServer.cast(__MODULE__, {:set_signal, bandwidth, spreading_factor})
  end

  @impl GenServer
  def init(_) do
    #
    # Couple notes:
    #   - /dev/spidev0.1 is the SPI device on the Raspberry Pi 2 B+
    #   - The :encoding option requires the fork of the :lora dependency at
    #     https://github.com/schrockwell/Elixir-LoRa/tree/add-encoding
    #
    {:ok, lora_pid} = LoRa.start_link(spi: "spidev0.1", encoding: :binary)

    LoRa.begin(lora_pid, 915.0e6)
    LoRa.set_spreading_factor(lora_pid, 10)
    LoRa.set_signal_bandwidth(lora_pid, 125.0e3)

    Logger.info("LoRa radio initialized")

    {:ok,
     %{
       lora_pid: lora_pid,
       pongs_received: [],
       ping_mode: nil,
       ping_client: nil,
       pinged_at: nil
     }}
  end

  @impl GenServer
  def handle_info({:lora, %{packet: packet} = message}, state) do
    case Packet.decode(packet) do
      {:ok, decoded} ->
        handle_packet(decoded, message, state)

      :error ->
        Logger.error("Unable to decode packet: #{inspect(packet)}")
        {:noreply, state}
    end
  end

  def handle_info(:stop_ping, state) do
    pongs = Enum.reverse(state.pongs_received)

    case state.ping_mode do
      :sync -> GenServer.reply(state.ping_client, pongs)
      :async -> send(state.ping_client, {__MODULE__, :ping_complete})
    end

    {:noreply, %{state | ping_client: nil, pongs_received: [], ping_mode: nil, pinged_at: nil}}
  end

  @impl GenServer
  def handle_cast({:start_ping_async, ping_client, ping_timeout}, state) do
    if state.ping_client do
      {:noreply, state}
    else
      LoRa.send(state.lora_pid, Packet.encode(:ping))

      Process.send_after(self(), :stop_ping, ping_timeout)

      {:noreply,
       %{
         state
         | ping_mode: :async,
           ping_client: ping_client,
           pinged_at: System.monotonic_time(:millisecond)
       }}
    end
  end

  def handle_cast({:set_signal, bandwidth, spreading_factor}, state) do
    LoRa.set_spreading_factor(state.lora_pid, spreading_factor)
    LoRa.set_signal_bandwidth(state.lora_pid, bandwidth)
    {:noreply, state}
  end

  @impl GenServer
  def handle_call({:start_ping_sync, ping_timeout}, from, state) do
    if state.ping_client do
      {:reply, {:error, :ping_in_progress}, state}
    else
      pinged_at = System.monotonic_time(:millisecond)

      LoRa.send(state.lora_pid, Packet.encode(:ping))

      Process.send_after(self(), :stop_ping, ping_timeout)

      {:noreply,
       %{
         state
         | ping_mode: :sync,
           ping_client: from,
           pinged_at: pinged_at
       }}
    end
  end

  defp handle_packet({:ping, _}, _, state) do
    pong_packet = Packet.encode(:pong, from: this_device_id())
    LoRa.send(state.lora_pid, pong_packet)

    {:noreply, state}
  end

  defp handle_packet({:pong, payload}, message, state) do
    if state.ping_mode != nil do
      Logger.debug("Pong received from #{payload.from}")

      pong_info = %{
        from: payload.from,
        rtt: {System.monotonic_time(:millisecond) - state.pinged_at, :ms},
        rssi: {message.rssi, :dBm},
        snr: {message.snr, :dB},
        time: message.time
      }

      if state.ping_mode == :async do
        send(state.ping_client, {__MODULE__, :pong, pong_info})
      end

      {:noreply, %{state | pongs_received: [pong_info | state.pongs_received]}}
    else
      {:noreply, state}
    end
  end

  defp handle_packet(unknown_packet, _, state) do
    Logger.error("Unable to handle packet: #{inspect(unknown_packet)}")
    {:noreply, state}
  end

  defp this_device_id, do: Nerves.Runtime.serial_number()
end
