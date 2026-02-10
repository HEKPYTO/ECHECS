defmodule Echecs.Bitboard.MagicGeneratorTest do
  use ExUnit.Case
  alias Echecs.Bitboard.Helper
  alias Echecs.Bitboard.MagicGenerator
  import Bitwise

  @tag timeout: :infinity
  test "find_magic finds a valid magic number for A1 rook" do
    sq = 0
    mask = MagicGenerator.mask_rook(sq)
    pop = Helper.pop_count(mask)
    expected_shift = 64 - pop

    result = MagicGenerator.find_magic(sq, :rook)

    assert result.sq == sq
    assert result.mask == mask
    assert result.shift == expected_shift
    assert is_integer(result.magic)
    assert is_binary(result.table)

    # Verify table size matches expected bits
    # Each entry is 64-bit (8 bytes). Size = 2^pop * 8
    expected_size = (1 <<< pop) * 8
    assert byte_size(result.table) == expected_size
  end
end
