defmodule Echecs.MoveGen do
  @moduledoc """
  Generates legal moves for a given game state using optimized bitboard operations.
  """

  import Bitwise
  alias Echecs.Bitboard.{Helper, Magic, Precomputed}
  alias Echecs.{Board, Game, Move, Piece}

  require Echecs.Move

  @doc """
  Returns a list of all legal moves for the current player.
  """
  def legal_moves(%Game{} = game) do
    generate_pseudo_moves_int(game)
    |> Enum.filter(&legal_int?(game, &1))
    |> Enum.map(&Move.to_struct/1)
  end

  @doc """
  Returns a list of pseudo-legal moves (ignoring check).
  """
  def pseudo_legal_moves(game) do
    generate_pseudo_moves_int(game)
    |> Enum.map(&Move.to_struct/1)
  end

  @doc """
  Generates pseudo-legal moves specifically for a piece type targeting a destination.
  Used for fast SAN parsing.
  """
  def generate_moves_targeting(game, target_sq, piece_type) do
    board = game.board
    turn = game.turn

    piece_bb =
      if turn == :white,
        do: Map.get(board, get_bb_key(:white, piece_type)),
        else: Map.get(board, get_bb_key(:black, piece_type))

    candidates_bb =
      case piece_type do
        :knight ->
          Precomputed.get_knight_attacks(target_sq) &&& piece_bb

        :bishop ->
          Magic.get_bishop_attacks(target_sq, board.all_pieces) &&& piece_bb

        :rook ->
          Magic.get_rook_attacks(target_sq, board.all_pieces) &&& piece_bb

        :queen ->
          (Magic.get_bishop_attacks(target_sq, board.all_pieces) |||
             Magic.get_rook_attacks(target_sq, board.all_pieces)) &&& piece_bb

        :king ->
          Precomputed.get_king_attacks(target_sq) &&& piece_bb

        :pawn ->
          reverse_pawn_moves(game, target_sq, turn)
      end

    if is_integer(candidates_bb) do
      bitboard_to_moves_to(candidates_bb, target_sq, [])
      |> Enum.map(&Move.to_struct/1)
    else
      candidates_bb |> Enum.map(&Move.to_struct/1)
    end
  end

  defp bitboard_to_moves_to(0, _, acc), do: acc

  defp bitboard_to_moves_to(bb, to, acc) do
    from = Helper.lsb(bb)
    bitboard_to_moves_to(bb &&& bb - 1, to, [Move.pack(from, to, nil, nil) | acc])
  end

  defp generate_pseudo_moves_int(%Game{board: board, turn: turn} = game) do
    us_bb = if turn == :white, do: board.white_pieces, else: board.black_pieces
    them_bb = if turn == :white, do: board.black_pieces, else: board.white_pieces
    all_bb = board.all_pieces

    []
    |> generate_pawn_moves(board, turn, them_bb, all_bb, game.en_passant)
    |> generate_knight_moves(board, turn, us_bb)
    |> generate_sliding_moves(:bishop, board, turn, us_bb, all_bb)
    |> generate_sliding_moves(:rook, board, turn, us_bb, all_bb)
    |> generate_sliding_moves(:queen, board, turn, us_bb, all_bb)
    |> generate_king_moves(board, turn, us_bb, game)
  end

  defp generate_pawn_moves(acc, board, :white, them_bb, all_bb, ep_sq) do
    pawns = board.white_pawns
    single_pushes = pawns >>> 8 &&& bnot(all_bb)
    acc = extract_pawn_moves(single_pushes, 8, :white, acc)

    rank_3_mask = 0x0000FF0000000000
    double_pushes = (single_pushes &&& rank_3_mask) >>> 8 &&& bnot(all_bb)
    acc = extract_pawn_double_moves(double_pushes, 16, acc)

    generate_pawn_captures(acc, pawns, :white, them_bb, ep_sq)
  end

  defp generate_pawn_moves(acc, board, :black, them_bb, all_bb, ep_sq) do
    pawns = board.black_pawns
    single_pushes = pawns <<< 8 &&& bnot(all_bb)
    acc = extract_pawn_moves(single_pushes, -8, :black, acc)

    rank_6_mask = 0x0000000000FF0000
    double_pushes = (single_pushes &&& rank_6_mask) <<< 8 &&& bnot(all_bb)
    acc = extract_pawn_double_moves(double_pushes, -16, acc)

    generate_pawn_captures(acc, pawns, :black, them_bb, ep_sq)
  end

  defp extract_pawn_moves(0, _, _, acc), do: acc

  defp extract_pawn_moves(targets, offset, color, acc) do
    to = Helper.lsb(targets)
    from = to + offset
    rank = div(to, 8)

    acc =
      if (color == :white and rank == 0) or (color == :black and rank == 7) do
        add_promotions(acc, from, to)
      else
        [Move.pack(from, to, nil, nil) | acc]
      end

    extract_pawn_moves(targets &&& targets - 1, offset, color, acc)
  end

  defp extract_pawn_double_moves(0, _, acc), do: acc

  defp extract_pawn_double_moves(targets, offset, acc) do
    to = Helper.lsb(targets)

    extract_pawn_double_moves(targets &&& targets - 1, offset, [
      Move.pack(to + offset, to, nil, nil) | acc
    ])
  end

  defp generate_pawn_captures(acc, pawns, color, them_bb, ep_sq) do
    ep_bb = if ep_sq, do: 1 <<< ep_sq, else: 0
    valid_targets = them_bb ||| ep_bb

    do_generate_pawn_captures(pawns, acc, color, valid_targets, ep_sq)
  end

  defp do_generate_pawn_captures(0, acc, _, _, _), do: acc

  defp do_generate_pawn_captures(pawns, acc, color, valid_targets, ep_sq) do
    from = Helper.lsb(pawns)
    attacks = Precomputed.get_pawn_attacks(from, color)
    captures = attacks &&& valid_targets

    acc = do_add_pawn_capture_moves(captures, acc, from, color, ep_sq)
    do_generate_pawn_captures(pawns &&& pawns - 1, acc, color, valid_targets, ep_sq)
  end

  defp do_add_pawn_capture_moves(0, acc, _, _, _), do: acc

  defp do_add_pawn_capture_moves(captures, acc, from, color, ep_sq) do
    to = Helper.lsb(captures)
    acc = add_pawn_capture_move(from, to, acc, color, ep_sq)
    do_add_pawn_capture_moves(captures &&& captures - 1, acc, from, color, ep_sq)
  end

  defp add_pawn_capture_move(from, to, m, color, ep_sq) do
    special = if to == ep_sq, do: :en_passant, else: nil
    rank = div(to, 8)

    if (color == :white and rank == 0) or (color == :black and rank == 7) do
      add_promotions(m, from, to)
    else
      [Move.pack(from, to, nil, special) | m]
    end
  end

  defp add_promotions(acc, from, to) do
    [:queen, :rook, :bishop, :knight]
    |> Enum.reduce(acc, fn p, a -> [Move.pack(from, to, p, nil) | a] end)
  end

  defp reverse_pawn_moves(game, to, :white) do
    board = game.board
    white_pawns = board.white_pawns
    moves = []

    moves = add_reverse_single_push(moves, to, white_pawns, board, 8)
    moves = add_reverse_double_push(moves, to, white_pawns, board, 16, 32..39)

    is_ep = game.en_passant == to
    target_occupied = Board.at(board, to) != nil and match?({:black, _}, Board.at(board, to))

    if is_ep or target_occupied do
      moves
      |> add_reverse_captures(to, white_pawns, is_ep, [9, 7])
      |> add_promo_if_needed(to)
    else
      add_promo_if_needed(moves, to)
    end
  end

  defp reverse_pawn_moves(game, to, :black) do
    board = game.board
    black_pawns = board.black_pawns
    moves = []

    moves = add_reverse_single_push_black(moves, to, black_pawns, board, -8)
    moves = add_reverse_double_push_black(moves, to, black_pawns, board, -16, 24..31)

    is_ep = game.en_passant == to
    target_occupied = Board.at(board, to) != nil and match?({:white, _}, Board.at(board, to))

    if is_ep or target_occupied do
      moves
      |> add_reverse_captures_black(to, black_pawns, is_ep, [-7, -9])
      |> add_promo_if_needed(to)
    else
      add_promo_if_needed(moves, to)
    end
  end

  defp add_reverse_single_push(moves, to, pawns, board, offset) do
    from = to + offset

    if from <= 63 and (pawns &&& 1 <<< from) != 0 and Board.at(board, to) == nil do
      [Move.pack(from, to, nil, nil) | moves]
    else
      moves
    end
  end

  defp add_reverse_double_push(moves, to, pawns, board, offset, range) do
    if to in range and Board.at(board, to) == nil and Board.at(board, to + div(offset, 2)) == nil do
      from = to + offset
      if (pawns &&& 1 <<< from) != 0, do: [Move.pack(from, to, nil, nil) | moves], else: moves
    else
      moves
    end
  end

  defp add_reverse_captures(moves, to, pawns, is_ep, offsets) do
    Enum.reduce(offsets, moves, fn offset, acc ->
      from = to + offset

      if from <= 63 and (pawns &&& 1 <<< from) != 0 and abs(rem(from, 8) - rem(to, 8)) == 1 do
        [create_pawn_move(from, to, is_ep) | acc]
      else
        acc
      end
    end)
  end

  defp add_reverse_single_push_black(moves, to, pawns, board, offset) do
    from = to + offset

    if from >= 0 and (pawns &&& 1 <<< from) != 0 and Board.at(board, to) == nil do
      [Move.pack(from, to, nil, nil) | moves]
    else
      moves
    end
  end

  defp add_reverse_double_push_black(moves, to, pawns, board, offset, range) do
    if to in range and Board.at(board, to) == nil and Board.at(board, to + div(offset, 2)) == nil do
      from = to + offset
      if (pawns &&& 1 <<< from) != 0, do: [Move.pack(from, to, nil, nil) | moves], else: moves
    else
      moves
    end
  end

  defp add_reverse_captures_black(moves, to, pawns, is_ep, offsets) do
    Enum.reduce(offsets, moves, fn offset, acc ->
      from = to + offset

      if from >= 0 and (pawns &&& 1 <<< from) != 0 and abs(rem(from, 8) - rem(to, 8)) == 1 do
        [create_pawn_move(from, to, is_ep) | acc]
      else
        acc
      end
    end)
  end

  defp add_promo_if_needed(moves, to) do
    rank = div(to, 8)

    if rank == 0 or rank == 7 do
      expand_promotions(moves)
    else
      moves
    end
  end

  defp expand_promotions(moves) do
    Enum.flat_map(moves, fn m ->
      [:queen, :rook, :bishop, :knight]
      |> Enum.map(fn p ->
        from = Move.unpack_from(m)
        to = Move.unpack_to(m)
        special = Move.unpack_special(m)
        Move.pack(from, to, p, special)
      end)
    end)
  end

  defp create_pawn_move(from, to, true), do: Move.pack(from, to, nil, :en_passant)
  defp create_pawn_move(from, to, false), do: Move.pack(from, to, nil, nil)

  defp generate_knight_moves(acc, board, turn, us_bb) do
    knights = if turn == :white, do: board.white_knights, else: board.black_knights
    do_generate_knight_moves(knights, acc, us_bb)
  end

  defp do_generate_knight_moves(0, acc, _), do: acc

  defp do_generate_knight_moves(knights, acc, us_bb) do
    from = Helper.lsb(knights)
    attacks = Precomputed.get_knight_attacks(from)
    valid_moves = attacks &&& bnot(us_bb)

    acc = bitboard_to_moves_from(valid_moves, from, acc)
    do_generate_knight_moves(knights &&& knights - 1, acc, us_bb)
  end

  defp bitboard_to_moves_from(0, _, acc), do: acc

  defp bitboard_to_moves_from(bb, from, acc) do
    to = Helper.lsb(bb)
    bitboard_to_moves_from(bb &&& bb - 1, from, [Move.pack(from, to, nil, nil) | acc])
  end

  defp generate_sliding_moves(acc, type, board, turn, us_bb, all_bb) do
    bb = get_slider_bb(board, turn, type)
    do_generate_sliding_moves(bb, acc, type, us_bb, all_bb)
  end

  defp do_generate_sliding_moves(0, acc, _, _, _), do: acc

  defp do_generate_sliding_moves(bb, acc, type, us_bb, all_bb) do
    from = Helper.lsb(bb)
    attacks = get_slider_attacks(type, from, all_bb)
    valid_moves = attacks &&& bnot(us_bb)

    acc = bitboard_to_moves_from(valid_moves, from, acc)
    do_generate_sliding_moves(bb &&& bb - 1, acc, type, us_bb, all_bb)
  end

  defp get_slider_bb(board, :white, :bishop), do: board.white_bishops
  defp get_slider_bb(board, :white, :rook), do: board.white_rooks
  defp get_slider_bb(board, :white, :queen), do: board.white_queens
  defp get_slider_bb(board, :black, :bishop), do: board.black_bishops
  defp get_slider_bb(board, :black, :rook), do: board.black_rooks
  defp get_slider_bb(board, :black, :queen), do: board.black_queens

  defp get_slider_attacks(:bishop, from, all_bb), do: Magic.get_bishop_attacks(from, all_bb)
  defp get_slider_attacks(:rook, from, all_bb), do: Magic.get_rook_attacks(from, all_bb)

  defp get_slider_attacks(:queen, from, all_bb),
    do: Magic.get_bishop_attacks(from, all_bb) ||| Magic.get_rook_attacks(from, all_bb)

  defp generate_king_moves(acc, board, turn, us_bb, game) do
    king_bb = if turn == :white, do: board.white_king, else: board.black_king

    if king_bb == 0 do
      acc
    else
      king_sq = Helper.lsb(king_bb)
      attacks = Precomputed.get_king_attacks(king_sq)
      valid_moves = attacks &&& bnot(us_bb)

      acc = bitboard_to_moves_from(valid_moves, king_sq, acc)
      generate_castling_moves(acc, king_sq, turn, game)
    end
  end

  defp generate_castling_moves(acc, king_sq, turn, game) do
    rights = Map.get(game.castling, turn, [])
    opponent = Piece.opponent(turn)

    if Game.in_check?(game) do
      acc
    else
      acc
      |> check_castling(:kingside, rights, king_sq, turn, game, opponent)
      |> check_castling(:queenside, rights, king_sq, turn, game, opponent)
    end
  end

  defp check_castling(acc, side, rights, king_sq, turn, game, opponent) do
    if side in rights and can_castle?(side, turn, game, opponent) do
      target = if side == :kingside, do: king_sq + 2, else: king_sq - 2
      special = if side == :kingside, do: :kingside_castle, else: :queenside_castle
      [Move.pack(king_sq, target, nil, special) | acc]
    else
      acc
    end
  end

  defp can_castle?(:kingside, :white, game, opponent) do
    kingside_clear?(game.board, :white) and not kingside_attacked?(game, opponent, :white)
  end

  defp can_castle?(:queenside, :white, game, opponent) do
    queenside_clear?(game.board, :white) and not queenside_attacked?(game, opponent, :white)
  end

  defp can_castle?(:kingside, :black, game, opponent) do
    kingside_clear?(game.board, :black) and not kingside_attacked?(game, opponent, :black)
  end

  defp can_castle?(:queenside, :black, game, opponent) do
    queenside_clear?(game.board, :black) and not queenside_attacked?(game, opponent, :black)
  end

  defp kingside_clear?(board, :white),
    do: Board.at(board, 61) == nil and Board.at(board, 62) == nil

  defp kingside_clear?(board, :black), do: Board.at(board, 5) == nil and Board.at(board, 6) == nil

  defp queenside_clear?(board, :white),
    do: Board.at(board, 59) == nil and Board.at(board, 58) == nil and Board.at(board, 57) == nil

  defp queenside_clear?(board, :black),
    do: Board.at(board, 3) == nil and Board.at(board, 2) == nil and Board.at(board, 1) == nil

  defp kingside_attacked?(game, opponent, :white) do
    Game.attacked?(game, 61, opponent) or Game.attacked?(game, 62, opponent)
  end

  defp kingside_attacked?(game, opponent, :black) do
    Game.attacked?(game, 5, opponent) or Game.attacked?(game, 6, opponent)
  end

  defp queenside_attacked?(game, opponent, :white) do
    Game.attacked?(game, 59, opponent) or Game.attacked?(game, 58, opponent)
  end

  defp queenside_attacked?(game, opponent, :black) do
    Game.attacked?(game, 3, opponent) or Game.attacked?(game, 2, opponent)
  end

  defp legal_int?(game, move_int) do
    board = Board.make_move_on_bitboards(game.board, move_int, game.turn)

    king_bb = if game.turn == :white, do: board.white_king, else: board.black_king
    king_sq = Helper.lsb(king_bb)

    if king_sq do
      opponent = Piece.opponent(game.turn)
      not Board.attacked?(board, king_sq, opponent)
    else
      false
    end
  end

  defp get_bb_key(:white, :pawn), do: :white_pawns
  defp get_bb_key(:white, :knight), do: :white_knights
  defp get_bb_key(:white, :bishop), do: :white_bishops
  defp get_bb_key(:white, :rook), do: :white_rooks
  defp get_bb_key(:white, :queen), do: :white_queens
  defp get_bb_key(:white, :king), do: :white_king
  defp get_bb_key(:black, :pawn), do: :black_pawns
  defp get_bb_key(:black, :knight), do: :black_knights
  defp get_bb_key(:black, :bishop), do: :black_bishops
  defp get_bb_key(:black, :rook), do: :black_rooks
  defp get_bb_key(:black, :queen), do: :black_queens
  defp get_bb_key(:black, :king), do: :black_king
end
