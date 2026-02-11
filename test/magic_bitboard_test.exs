defmodule Echecs.Core.MagicBitboardTest do
  use ExUnit.Case
  alias Echecs.Bitboard.{Helper, Magic, MagicGenerator}
  import Bitwise

  @moduledoc """
  Tests for Magic Bitboard generation and attack lookups.
  Combines previous MagicTest and MagicGeneratorTest.
  """

  # Only test loading if Magic is initialized (it usually is by app start)
  setup_all do
    # Ensure magic tables are loaded if not already
    try do
      Magic.get_rook_attacks(0, 0)
    rescue
      _ -> Magic.init()
    end

    :ok
  end

  describe "Magic Generator" do
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

  describe "Magic Lookups" do
    test "Rook attacks on empty board" do
      # A1 (0) on empty board should attack file A and Rank 1
      attacks = Magic.get_rook_attacks(0, 0)

      # B1 (1), H1 (7)
      assert (attacks &&& 1 <<< 1) != 0
      assert (attacks &&& 1 <<< 7) != 0
      # A2 (8), A8 (56)
      assert (attacks &&& 1 <<< 8) != 0
      assert (attacks &&& 1 <<< 56) != 0

      # Non-attacked: B2 (9)
      assert (attacks &&& 1 <<< 9) == 0
    end

    test "Rook attacks with blocker" do
      # Rook on A1 (0), Blocker on A4 (24)
      blocker = 1 <<< 24
      attacks = Magic.get_rook_attacks(0, blocker)

      # A2 (8), A3 (16) -> Open
      assert (attacks &&& 1 <<< 8) != 0
      assert (attacks &&& 1 <<< 16) != 0
      # A4 (24) -> Capture
      assert (attacks &&& 1 <<< 24) != 0
      # A5 (32) -> Blocked
      assert (attacks &&& 1 <<< 32) == 0
    end

    test "Bishop attacks on empty board" do
      # Bishop on D4 (27)
      # Diagonals: C3, B2, A1, E5, F6, G7, H8, C5, B6, A7, E3, F2, G1
      sq = 27
      attacks = Magic.get_bishop_attacks(sq, 0)

      # C3 (18), A1 (0), H8 (63)
      assert (attacks &&& 1 <<< 18) != 0
      assert (attacks &&& 1 <<< 0) != 0
      assert (attacks &&& 1 <<< 63) != 0

      # Non-attacked: E4 (28) (next to it horizontally)
      assert (attacks &&& 1 <<< 28) == 0
    end
  end
end
