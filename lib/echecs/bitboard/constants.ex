defmodule Echecs.Bitboard.Constants do
  @moduledoc "Constants for Bitboard operations"

  defmacro rank_1, do: 0x00000000000000FF
  defmacro rank_2, do: 0x000000000000FF00
  defmacro rank_7, do: 0x00FF000000000000
  defmacro rank_8, do: 0xFF00000000000000

  defmacro file_a, do: 0x0101010101010101
  defmacro file_h, do: 0x8080808080808080
end
