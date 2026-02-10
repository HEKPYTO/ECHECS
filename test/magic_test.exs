defmodule Echecs.Bitboard.MagicTest do
  use ExUnit.Case
  alias Echecs.Bitboard.Magic
  import Bitwise

  setup_all do
    Magic.init()
    :ok
  end

  test "Magic table loading" do
    # Simply check if we can get attacks without crashing
    attacks = Magic.get_rook_attacks(0, 0)
    assert attacks != 0
  end

  test "Rook attacks on empty board" do
    # A1 (0) on empty board should attack file A and Rank 1
    # Files: A=0x0101010101010101, H=0x80...
    # Ranks: 1=0xFF, 8=0xFF...

    # Expected for A1: Rank 1 (excluding self) | File A (excluding self)
    # Rank 1: b1..h1 (squares 1..7)
    # File A: a2..a8 (squares 8, 16, 24, 32, 40, 48, 56)

    attacks = Magic.get_rook_attacks(0, 0)

    # Check specific squares
    # B1
    assert (attacks &&& 1 <<< 1) != 0
    # H1
    assert (attacks &&& 1 <<< 7) != 0
    # A2
    assert (attacks &&& 1 <<< 8) != 0
    # A8
    assert (attacks &&& 1 <<< 56) != 0

    # Check non-attacked
    # B2
    assert (attacks &&& 1 <<< 9) == 0
  end

  test "Rook attacks with blocker" do
    # Rook on A1 (0), Blocker on A4 (24)
    # Should attack A2, A3, A4 (capture) but NOT A5..A8

    blocker = 1 <<< 24
    attacks = Magic.get_rook_attacks(0, blocker)

    # A2
    assert (attacks &&& 1 <<< 8) != 0
    # A3
    assert (attacks &&& 1 <<< 16) != 0
    # A4 (Capture)
    assert (attacks &&& 1 <<< 24) != 0
    # A5 (Blocked)
    assert (attacks &&& 1 <<< 32) == 0
  end

  test "Bishop attacks on empty board" do
    # Bishop on D4 (27)
    # Diagonals: C3, B2, A1, E5, F6, G7, H8, C5, B6, A7, E3, F2, G1

    sq = 27
    attacks = Magic.get_bishop_attacks(sq, 0)

    # C3
    assert (attacks &&& 1 <<< 18) != 0
    # A1
    assert (attacks &&& 1 <<< 0) != 0
    # H8
    assert (attacks &&& 1 <<< 63) != 0

    # Check non-attacked
    # E4 (next to it)
    assert (attacks &&& 1 <<< 28) == 0
  end
end
