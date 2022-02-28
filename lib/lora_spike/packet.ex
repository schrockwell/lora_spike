defmodule LoraSpike.Packet do
  @ping 0x00
  @pong 0x01

  def encode(type, opts \\ [])

  def encode(:ping, _) do
    <<@ping>>
  end

  def encode(:pong, opts) do
    from = Keyword.fetch!(opts, :from)
    <<@pong, from::binary>>
  end

  def decode(<<@ping>>) do
    {:ok, {:ping, %{}}}
  end

  def decode(<<@pong, from::binary>>) do
    {:ok, {:pong, %{from: from}}}
  end

  def decode(_) do
    :error
  end
end
