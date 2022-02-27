defmodule LoraSpike.Display do
  use Vivid

  @frame_width 128
  @frame_height 32
  @display :display

  def display_serial do
    frame = Frame.init(@frame_width, @frame_height, RGBA.black())

    text = Font.line("hello world", 0.5)

    buffer =
      frame
      |> Frame.push(text, RGBA.white())
      |> Frame.buffer(:horizontal)
      |> buffer2bitstring()

    SSD1306.Device.display(@display, buffer)
  end

  def display_point(point) do
    buffer =
      for i <- 0..(@frame_height * @frame_width - 1), reduce: <<>> do
        acc ->
          if i == point do
            <<acc::bitstring, 1::1>>
          else
            <<acc::bitstring, 0::1>>
          end
      end

    SSD1306.Device.display(@display, buffer)
  end

  def animate_all_points do
    for point <- 1..(@frame_height * @frame_width)//2 do
      display_point(point)
    end
  end

  defp buffer2bitstring(buffer) do
    points = Enum.to_list(buffer)

    # for point <- points, reduce: <<>> do
    #   acc ->
    #     if point == RGBA.black() do
    #       <<acc::bitstring, 0::1>>
    #     else
    #       <<acc::bitstring, 1::1>>
    #     end
    #   end

    rows = trunc(@frame_height / 8)
    cols = @frame_width

    for row <- 0..(rows - 1), col <- 0..(cols - 1), bit <- 0..7, reduce: <<>> do
      acc ->
        address = (row * 8 + bit) * cols + col

        point = Enum.at(points, address)

        if point == RGBA.black() do
          <<acc::bitstring, 0::1>>
        else
          <<acc::bitstring, 1::1>>
        end
    end
  end
end
