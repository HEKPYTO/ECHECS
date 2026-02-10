defmodule Echecs.Bitboard.Helper do
  @moduledoc """
  Low-level bit manipulation helpers for Bitboards.
  """
  import Bitwise

  require Echecs.Bitboard.Constants
  alias Echecs.Bitboard.Constants

  @debruijn64 0x03F79D71B4CB0A89
  @index64 {
    0,
    1,
    48,
    2,
    57,
    49,
    28,
    3,
    61,
    58,
    50,
    42,
    38,
    29,
    17,
    4,
    62,
    55,
    59,
    36,
    53,
    51,
    43,
    22,
    45,
    39,
    33,
    30,
    24,
    18,
    12,
    5,
    63,
    47,
    56,
    27,
    60,
    41,
    37,
    16,
    54,
    35,
    52,
    21,
    44,
    32,
    23,
    11,
    46,
    26,
    40,
    15,
    34,
    20,
    31,
    10,
    25,
    14,
    19,
    9,
    13,
    8,
    7,
    6
  }

  @compile {:inline,
            lsb: 1,
            pop_count: 1,
            shift_north: 1,
            shift_south: 1,
            shift_east: 1,
            shift_west: 1,
            shift_north_east: 1,
            shift_north_west: 1,
            shift_south_east: 1,
            shift_south_west: 1}

  @doc "Returns the index (0-63) of the least significant bit. Returns nil if 0."
  def lsb(0), do: nil

  def lsb(bb) do
    isolated = bb &&& -bb
    prod = isolated * @debruijn64 &&& 0xFFFFFFFFFFFFFFFF
    idx = prod >>> 58
    elem(@index64, idx)
  end

  @doc "Returns the number of set bits (population count)"
  def pop_count(bb) do
    bb = bb - (bb >>> 1 &&& 0x5555555555555555)
    bb = (bb &&& 0x3333333333333333) + (bb >>> 2 &&& 0x3333333333333333)
    bb = bb + (bb >>> 4) &&& 0x0F0F0F0F0F0F0F0F
    (bb * 0x0101010101010101 &&& 0xFFFFFFFFFFFFFFFF) >>> 56
  end

  @doc "Shifts a bitboard in a direction. handles wrapping."
  def shift_north(bb), do: bb >>> 8
  def shift_south(bb), do: bb <<< 8
  def shift_east(bb), do: (bb &&& bnot(Constants.file_h())) <<< 1
  def shift_west(bb), do: (bb &&& bnot(Constants.file_a())) >>> 1

  def shift_north_east(bb), do: (bb &&& bnot(Constants.file_h())) >>> 7
  def shift_north_west(bb), do: (bb &&& bnot(Constants.file_a())) >>> 9
  def shift_south_east(bb), do: (bb &&& bnot(Constants.file_h())) <<< 9
  def shift_south_west(bb), do: (bb &&& bnot(Constants.file_a())) <<< 7
end
