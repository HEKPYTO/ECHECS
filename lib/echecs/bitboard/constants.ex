defmodule Echecs.Bitboard.Constants do
  @moduledoc "Constants for Bitboard operations"

  defmacro rank_1, do: 0x00000000000000FF
  defmacro rank_2, do: 0x000000000000FF00
  defmacro rank_7, do: 0x00FF000000000000
  defmacro rank_8, do: 0xFF00000000000000

  defmacro file_a, do: 0x0101010101010101
  defmacro file_h, do: 0x8080808080808080

  defmacro mask64, do: 0xFFFFFFFFFFFFFFFF

  # Castling path masks (bitwise emptiness checks)
  # White kingside: f1(61) and g1(62) must be empty
  defmacro white_ks_path, do: 0x6000000000000000
  # White queenside: b1(57), c1(58), d1(59) must be empty
  defmacro white_qs_path, do: 0x0E00000000000000
  # Black kingside: f8(5) and g8(6) must be empty
  defmacro black_ks_path, do: 0x0000000000000060
  # Black queenside: b8(1), c8(2), d8(3) must be empty
  defmacro black_qs_path, do: 0x000000000000000E
end
