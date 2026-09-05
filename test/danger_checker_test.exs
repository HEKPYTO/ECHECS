defmodule Echecs.DangerCheckerTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias Echecs.{Board, Game, MoveGen, Piece}

  # Cross-check for the check-detection fast path in MoveGen: the king-removed
  # "danger" board reports check (danger & king != 0) exactly when the true
  # checker set is non-empty. Both sides are observed through public API only:
  # Game.in_check?/1 (full occupancy, via Board.attacked?/3) versus
  # Board.attacked?/3 on the board with the side-to-move king bit cleared
  # (the occ_no_king view). Any divergence fails loudly.
  #
  # Square convention (Echecs.Board.to_index): a8 = 0, h1 = 63,
  # i.e. index = (8 - rank) * 8 + (file - ?a).

  @mask64 0xFFFFFFFFFFFFFFFF

  # FEN, king square, expected in_check?, move-shape expectation.
  @cases [
    # Startpos: no check.
    {"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", "e1", false, :open},
    # Black rook e8 down the open e-file: single rook check on Ke1.
    {"4r3/8/8/8/8/8/5PPP/4K2R w - - 0 1", "e1", true, :single},
    # Rook e8 plus bishop b4 (b4-c3-d2-e1): double check on Ke1.
    # Only king moves are legal.
    {"4r3/8/8/8/1b6/8/5PPP/4K2R w - - 0 1", "e1", true, :double},
    # Knight d3 (attacks c1, e1, f2, ...): single knight check on Ke1.
    {"8/8/8/8/8/3n4/5PPP/4K2R w - - 0 1", "e1", true, :single},
    # Black pawn d2 (attacks c1, e1): single pawn check on Ke1.
    {"8/8/8/8/8/8/3p1PPP/4K2R w - - 0 1", "e1", true, :single},
    # White rook e2 interposes on the e-file: pinned piece, Ke1 NOT in check.
    {"4r3/8/8/8/8/8/4R1PP/4K2R w - - 0 1", "e1", false, :open}
  ]

  # Bitboard-tuple layout (cf. Echecs.Board): 0..5 white P N B R Q K,
  # 6..11 black P N B R Q K, 12 white occ, 13 black occ, 14 all occ.
  defp without_king(board, king_sq, :white),
    do: clear_bit(clear_bit(clear_bit(board, 5, king_sq), 12, king_sq), 14, king_sq)

  defp without_king(board, king_sq, :black),
    do: clear_bit(clear_bit(clear_bit(board, 11, king_sq), 13, king_sq), 14, king_sq)

  defp clear_bit(board, elem_idx, sq),
    do: put_elem(board, elem_idx, elem(board, elem_idx) &&& bxor(@mask64, 1 <<< sq))

  test "danger (king removed) agrees with checker set on checks, pins and quiet positions" do
    for {fen, king_alg, expected_check, kind} <- @cases do
      game = Game.new(fen)
      assert is_tuple(game.board), "expected tuple board for #{fen}"
      king_sq = Board.to_index(king_alg)
      opponent = Piece.opponent(game.turn)

      full = Board.attacked?(game.board, king_sq, opponent)
      no_king = Board.attacked?(without_king(game.board, king_sq, game.turn), king_sq, opponent)
      in_check = Game.in_check?(game)

      assert in_check == expected_check, "hand-derived check expectation failed: #{fen}"
      assert in_check == full, "full-occupancy attack disagrees with in_check?: #{fen}"

      assert in_check == no_king,
             "RISK-4: king-removed danger (#{no_king}) disagrees with checker set (#{in_check}): #{fen}"

      moves = MoveGen.legal_moves(game)

      if kind == :double do
        assert moves != [],
               "double check must still leave king moves: #{fen}"

        assert Enum.all?(moves, &(&1.from == king_sq)),
               "double check must leave king-only moves: #{fen}"
      end
    end
  end
end
