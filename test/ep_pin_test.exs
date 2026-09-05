defmodule Echecs.EnPassantPinTest do
  use ExUnit.Case, async: true

  alias Echecs.{Board, Game, MoveGen}

  # Regression tests for the two classic en-passant pin gotchas
  # (cf. peterellisjones' well-known EP edge cases):
  #
  #   (a) Double-blocker EP discovered check: the capturing pawn AND the
  #       captured pawn both leave their squares, so a slider pin test must
  #       consider BOTH squares vacated. A naive "is the capturing pawn
  #       pinned?" check sees two blockers between king and slider, concludes
  #       "not pinned", and wrongly allows the capture.
  #   (b) Horizontal rook/queen re-check after EP removal: legality must be
  #       re-evaluated against the occupancy AFTER removing both pawns (the
  #       landing square is on another rank and does not block the ray), and
  #       the attacker set must include queens as well as rooks.
  #
  # Square convention (Echecs.Board.to_index): a8 = 0, h1 = 63,
  # i.e. index = (8 - rank) * 8 + (file - ?a).

  # Rank 5: Ka5, white pawn b5, black pawn c5 (just pushed c7-c5), black
  # rook h5. White to move, EP square c6.
  #
  #   8 . . . . . . . .
  #   7 . . . . . . . .
  #   6 . . . . . . . .
  #   5 K P p . . . . r
  #   4 . . . . . . . .
  #
  # Hand derivation: b5xc6 e.p. removes BOTH b5 and c5 from rank 5, landing
  # the white pawn on c6. Rank 5 becomes K . . . . . . r, so the h5 rook
  # x-rays the a5 king: the capture leaves White in check and is ILLEGAL.
  # White's remaining legal moves are the 4 king steps
  # (a6, b6, a4, b4); no en-passant move may appear.
  @rook_ep_illegal_fen "8/8/8/KPp4r/8/8/8/8 w - c6 0 1"

  # Same geometry with a black QUEEN on h5 instead of a rook.
  # Hand derivation: identical to the rook case -- after b5xc6 e.p. rank 5
  # is K . . . . . . q and the queen attacks along the rank. The generator
  # must test rooks OR queens here (gotcha (b)); a rook-only re-check would
  # wrongly allow this capture. ILLEGAL, 4 king moves, no EP move.
  @queen_ep_illegal_fen "8/8/8/KPp4q/8/8/8/8 w - c6 0 1"

  # Control: identical pawns/king, but the black rook is on h3 (rank 3),
  # off the 5th rank.
  #
  # Hand derivation: b5xc6 e.p. still removes b5 and c5, landing on c6, but
  # no black slider shares rank 5 (or any ray onto a5/c6 that the removal
  # opens), so the a5 king is safe and the capture is LEGAL. Expect the
  # EP move b5 -> c6 plus the same 4 king steps = 5 legal moves.
  @rook_off_rank_legal_fen "8/8/8/KPp5/8/7r/8/8 w - c6 0 1"

  # Black-to-move mirror of the double-blocker on rank 4: black king a4,
  # black pawn b4, white pawn c4 (just pushed c2-c4), white rook h4.
  # Black to move, EP square c3.
  #
  # Hand derivation: b4xc3 e.p. removes BOTH b4 and c4 from rank 4, landing
  # the black pawn on c3. Rank 4 becomes k . . . . . . R, so the h4 rook
  # x-rays the a4 king: ILLEGAL. Black keeps the 4 king steps
  # (a5, b5, a3, b3); no en-passant move may appear.
  @black_mirror_illegal_fen "8/8/8/8/kpP4R/8/8/8 b - c3 0 1"

  describe "en passant pin edge cases" do
    test "double-blocker EP discovered check is illegal (rook on 5th rank)" do
      game = Game.new(@rook_ep_illegal_fen)
      moves = MoveGen.legal_moves(game)

      ep_from = Board.to_index("b5")
      ep_to = Board.to_index("c6")

      assert Enum.filter(moves, &(&1.special == :en_passant)) == [],
             "b5xc6 e.p. must be excluded: it uncovers Rh5-a5"

      refute Enum.any?(moves, &(&1.from == ep_from and &1.to == ep_to)),
             "the b5 -> c6 capture must not be a legal move"

      # Sanity: only the 4 king steps remain, so generation itself is intact.
      assert length(moves) == 4
    end

    test "horizontal queen re-check after EP removal is illegal" do
      game = Game.new(@queen_ep_illegal_fen)
      moves = MoveGen.legal_moves(game)

      ep_from = Board.to_index("b5")
      ep_to = Board.to_index("c6")

      assert Enum.filter(moves, &(&1.special == :en_passant)) == [],
             "b5xc6 e.p. must be excluded: it uncovers Qh5-a5"

      refute Enum.any?(moves, &(&1.from == ep_from and &1.to == ep_to)),
             "the b5 -> c6 capture must not be a legal move"

      assert length(moves) == 4
    end

    test "legal EP control: slider off the rank allows the capture" do
      game = Game.new(@rook_off_rank_legal_fen)
      moves = MoveGen.legal_moves(game)

      ep_from = Board.to_index("b5")
      ep_to = Board.to_index("c6")

      ep_moves = Enum.filter(moves, &(&1.special == :en_passant))
      assert length(ep_moves) == 1

      assert Enum.any?(
               moves,
               &(&1.from == ep_from and &1.to == ep_to and &1.special == :en_passant)
             ),
             "b5xc6 e.p. must be legal when no slider shares the rank"

      # 4 king steps + the EP capture.
      assert length(moves) == 5
    end

    test "black-to-move mirror of the double-blocker is illegal" do
      game = Game.new(@black_mirror_illegal_fen)
      moves = MoveGen.legal_moves(game)

      ep_from = Board.to_index("b4")
      ep_to = Board.to_index("c3")

      assert Enum.filter(moves, &(&1.special == :en_passant)) == [],
             "b4xc3 e.p. must be excluded: it uncovers Rh4-a4"

      refute Enum.any?(moves, &(&1.from == ep_from and &1.to == ep_to)),
             "the b4 -> c3 capture must not be a legal move"

      assert length(moves) == 4
    end
  end

  describe "EP check_mask / pin-filter isolation (B16/B17/B19-false)" do
    # B16 -- file-pinned pawn with an off-ray capture available.
    #
    #   8 . . . . r . . .
    #   3 . . . p . p . .
    #   2 . . . . P . . .
    #   1 . . . . K . . .
    #
    # Hand derivation: Re8 pins Pe2 to Ke1 down the e-file (single blocker
    # e2, so pin_mask[e2] is the e-file ray). Captures e2xd3 / e2xf3 leave
    # the ray and are excluded by the pin filter; pushes e2-e3 / e2-e4 stay
    # on the ray and remain legal. The black pawns on d3/f3 attack e2 but
    # do not check Ke1, so check_mask is full -- exclusion comes from the
    # pin filter alone. Expect 2 pawn pushes + 4 king steps = 6 moves.
    test "pinned pawn: off-ray captures absent, on-ray pushes present" do
      game = Game.new("4r3/8/8/8/8/3p1p2/4P3/4K3 w - - 0 1")
      moves = MoveGen.legal_moves(game)

      e2 = Board.to_index("e2")
      d3 = Board.to_index("d3")
      f3 = Board.to_index("f3")
      e3 = Board.to_index("e3")
      e4 = Board.to_index("e4")

      refute Enum.any?(moves, &(&1.from == e2 and &1.to == d3)),
             "e2xd3 must be excluded: it leaves the e-file pin ray"

      refute Enum.any?(moves, &(&1.from == e2 and &1.to == f3)),
             "e2xf3 must be excluded: it leaves the e-file pin ray"

      assert Enum.any?(moves, &(&1.from == e2 and &1.to == e3)),
             "e2-e3 stays on the pin ray and must be legal"

      assert Enum.any?(moves, &(&1.from == e2 and &1.to == e4)),
             "e2-e4 stays on the pin ray and must be legal"

      assert length(moves) == 6
    end

    # B17 -- side in check with EP available, but neither ep_sq nor cap_sq
    # lies on the check_mask.
    #
    #   8 . . . . r . . .
    #   5 . . p P . . . .
    #   1 . . . . K . . .
    #
    # Hand derivation: Re8 checks Ke1 down the e-file, so check_mask is
    # e2..e8 plus e8. EP is available (black just pushed c7-c5, ep square
    # c6, attacker d5), but neither c6 (ep_sq) nor c5 (cap_sq) lies on the
    # check_mask, so ep_valid is FALSE and no EP move may appear. The d5
    # pawn cannot reach the e-file, so all that remains are the 4 king
    # steps (d1, f1, d2, f2); e2 is covered by the rook.
    test "in check off the EP squares: zero EP moves" do
      game = Game.new("4r3/8/8/2pP4/8/8/8/4K3 w - c6 0 1")
      moves = MoveGen.legal_moves(game)

      king = Board.to_index("e1")

      assert Enum.filter(moves, &(&1.special == :en_passant)) == [],
             "d5xc6 e.p. neither blocks the e-file check nor captures the checker"

      assert length(moves) == 4
      assert Enum.all?(moves, &(&1.from == king))
    end

    # B19-false -- pin_ok TRUE (capturing pawn unpinned) but the post-EP
    # removal exposes the king to a rook on the rank.
    #
    #   5 r . . p P . K .
    #
    # Hand derivation: between Ra5 and Kg5 stand TWO blockers (d5 and e5),
    # so Pe5 is NOT pinned and pin_ok for e5xd6 e.p. is TRUE. The capture
    # removes BOTH d5 and e5 from rank 5, landing on d6 and leaving
    # r . . . . . K .: the rook x-rays the king, so the occ_after rook
    # re-check must exclude it. Proof the pin filter is not the excluder:
    # the plain push e5-e6 is legal (unpinned pawn moves freely). Expect
    # 8 king steps + the e5-e6 push = 9 moves, no EP move.
    test "unpinned EP pawn still illegal via rank x-ray after removal" do
      game = Game.new("8/8/8/r2pP1K1/8/8/8/8 w - d6 0 1")
      moves = MoveGen.legal_moves(game)

      ep_from = Board.to_index("e5")
      ep_to = Board.to_index("d6")
      push_to = Board.to_index("e6")

      assert Enum.filter(moves, &(&1.special == :en_passant)) == [],
             "e5xd6 e.p. must be excluded: it uncovers Ra5-g5"

      refute Enum.any?(moves, &(&1.from == ep_from and &1.to == ep_to)),
             "the e5 -> d6 capture must not be a legal move"

      assert Enum.any?(moves, &(&1.from == ep_from and &1.to == push_to)),
             "e5-e6 must stay legal: the pawn is unpinned (pin_ok TRUE)"

      assert length(moves) == 9
    end
  end
end
