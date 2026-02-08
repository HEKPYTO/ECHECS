defmodule Echecs.MoveGen do
  @moduledoc """
  Generates legal moves for a given game state.
  """

  alias Echecs.{Board, Game, Move, Piece}

  @doc """
  Returns a list of all legal moves for the current player.
  """
  def legal_moves(%Game{} = game) do
    pseudo_legal_moves(game)
    |> Enum.filter(&legal?(game, &1))
  end

  @doc """
  Returns a list of pseudo-legal moves (ignoring check).
  """
  def pseudo_legal_moves(%Game{board: board, turn: turn} = game) do
    0..63
    |> Enum.filter(fn idx ->
      case Board.at(board, idx) do
        {^turn, _} -> true
        _ -> false
      end
    end)
    |> Enum.flat_map(fn idx ->
      piece = Board.at(board, idx)
      generate_moves(piece, idx, game)
    end)
  end

  defp generate_moves({color, :pawn}, idx, game), do: pawn_moves(color, idx, game)
  defp generate_moves({_, :knight}, idx, game), do: knight_moves(idx, game)
  defp generate_moves({_, :bishop}, idx, game), do: sliding_moves(idx, game, [-9, -7, 7, 9])
  defp generate_moves({_, :rook}, idx, game), do: sliding_moves(idx, game, [-8, -1, 1, 8])

  defp generate_moves({_, :queen}, idx, game),
    do: sliding_moves(idx, game, [-9, -8, -7, -1, 1, 7, 8, 9])

  defp generate_moves({_, :king}, idx, game), do: king_moves(idx, game)

  defp pawn_moves(:white, idx, game) do
    forward_moves(:white, idx, game) ++ capture_moves(:white, idx, game)
  end

  defp pawn_moves(:black, idx, game) do
    forward_moves(:black, idx, game) ++ capture_moves(:black, idx, game)
  end

  defp forward_moves(:white, idx, game) do
    target = idx - 8

    if target >= 0 and Board.at(game.board, target) == nil do
      moves = [Move.new(idx, target)]

      if div(idx, 8) == 6 and Board.at(game.board, target - 8) == nil do
        [Move.new(idx, target - 8) | moves]
      else
        moves
      end
    else
      []
    end
    |> add_promotions(idx, :white)
  end

  defp forward_moves(:black, idx, game) do
    target = idx + 8

    if target <= 63 and Board.at(game.board, target) == nil do
      moves = [Move.new(idx, target)]

      if div(idx, 8) == 1 and Board.at(game.board, target + 8) == nil do
        [Move.new(idx, target + 8) | moves]
      else
        moves
      end
    else
      []
    end
    |> add_promotions(idx, :black)
  end

  defp capture_moves(:white, idx, game) do
    [-9, -7]
    |> Enum.reduce([], fn offset, acc ->
      target = idx + offset

      if valid_pawn_capture?(:white, idx, target, game),
        do: [create_pawn_capture(idx, target, game) | acc],
        else: acc
    end)
    |> add_promotions(idx, :white)
  end

  defp capture_moves(:black, idx, game) do
    [7, 9]
    |> Enum.reduce([], fn offset, acc ->
      target = idx + offset

      if valid_pawn_capture?(:black, idx, target, game),
        do: [create_pawn_capture(idx, target, game) | acc],
        else: acc
    end)
    |> add_promotions(idx, :black)
  end

  defp valid_pawn_capture?(:white, idx, target, game) do
    target >= 0 and abs(rem(idx, 8) - rem(target, 8)) == 1 and
      (enemy?(game, target, :black) or target == game.en_passant)
  end

  defp valid_pawn_capture?(:black, idx, target, game) do
    target <= 63 and abs(rem(idx, 8) - rem(target, 8)) == 1 and
      (enemy?(game, target, :white) or target == game.en_passant)
  end

  defp enemy?(game, target, enemy_color) do
    content = Board.at(game.board, target)
    content != nil and elem(content, 0) == enemy_color
  end

  defp create_pawn_capture(idx, target, game) do
    if target == game.en_passant do
      Move.new(idx, target, nil, :en_passant)
    else
      Move.new(idx, target)
    end
  end

  defp add_promotions(moves, from_idx, color) do
    rank = div(from_idx, 8)
    promo = (color == :white and rank == 1) or (color == :black and rank == 6)

    if promo do
      Enum.flat_map(moves, &promotions(&1, color))
    else
      moves
    end
  end

  defp promotions(move, color) do
    to_rank = div(move.to, 8)

    if (color == :white and to_rank == 0) or (color == :black and to_rank == 7) do
      [:queen, :rook, :bishop, :knight]
      |> Enum.map(fn type -> %{move | promotion: type} end)
    else
      [move]
    end
  end

  defp knight_moves(idx, game) do
    [-17, -15, -10, -6, 6, 10, 15, 17]
    |> Enum.map(&(&1 + idx))
    |> Enum.filter(fn target ->
      target in 0..63 and
        valid_knight_jump?(idx, target) and
        valid_target?(game, target)
    end)
    |> Enum.map(&Move.new(idx, &1))
  end

  defp valid_knight_jump?(from, to) do
    abs(rem(from, 8) - rem(to, 8)) + abs(div(from, 8) - div(to, 8)) == 3
  end

  defp valid_target?(game, target) do
    content = Board.at(game.board, target)
    content == nil or elem(content, 0) != game.turn
  end

  defp sliding_moves(start_idx, game, offsets) do
    Enum.flat_map(offsets, fn offset ->
      slide(start_idx, start_idx + offset, offset, game.board, game.turn, [])
    end)
  end

  defp slide(start_idx, current_idx, offset, board, color, acc) do
    if on_board?(current_idx - offset, current_idx) do
      content = Board.at(board, current_idx)

      cond do
        content == nil ->
          new_acc = [Move.new(start_idx, current_idx) | acc]
          slide(start_idx, current_idx + offset, offset, board, color, new_acc)

        elem(content, 0) != color ->
          [Move.new(start_idx, current_idx) | acc]

        true ->
          acc
      end
    else
      acc
    end
  end

  defp on_board?(from_idx, to_idx) do
    to_idx in 0..63 and abs(rem(from_idx, 8) - rem(to_idx, 8)) <= 1
  end

  defp king_moves(idx, game) do
    offsets = [-9, -8, -7, -1, 1, 7, 8, 9]
    col = rem(idx, 8)

    moves =
      Enum.reduce(offsets, [], fn offset, acc ->
        target = idx + offset
        if valid_king_target?(target, col, game), do: [Move.new(idx, target) | acc], else: acc
      end)

    moves ++ castling_moves(idx, game)
  end

  defp valid_king_target?(target, col, game) do
    target_col = rem(target, 8)

    target in 0..63 and
      abs(col - target_col) <= 1 and
      not occupied_by_ally?(game.board, target, game.turn)
  end

  defp occupied_by_ally?(board, target, turn) do
    content = Board.at(board, target)
    content != nil and elem(content, 0) == turn
  end

  defp castling_moves(idx, game) do
    start_pos = if game.turn == :white, do: 60, else: 4

    if idx == start_pos do
      rights = Map.get(game.castling, game.turn, [])
      opponent = Piece.opponent(game.turn)

      ks =
        if :kingside in rights and can_castle_ks?(game, opponent),
          do: [Move.new(idx, idx + 2, nil, :kingside_castle)],
          else: []

      qs =
        if :queenside in rights and can_castle_qs?(game, opponent),
          do: [Move.new(idx, idx - 2, nil, :queenside_castle)],
          else: []

      ks ++ qs
    else
      []
    end
  end

  defp can_castle_ks?(game, opponent) do
    kingside_clear?(game.board, game.turn) and not kingside_attacked?(game, opponent, game.turn)
  end

  defp can_castle_qs?(game, opponent) do
    queenside_clear?(game.board, game.turn) and not queenside_attacked?(game, opponent, game.turn)
  end

  defp kingside_clear?(board, :white) do
    Board.at(board, 61) == nil and Board.at(board, 62) == nil
  end

  defp kingside_clear?(board, :black), do: Board.at(board, 5) == nil and Board.at(board, 6) == nil

  defp queenside_clear?(board, :white),
    do: Board.at(board, 59) == nil and Board.at(board, 58) == nil and Board.at(board, 57) == nil

  defp queenside_clear?(board, :black),
    do: Board.at(board, 3) == nil and Board.at(board, 2) == nil and Board.at(board, 1) == nil

  defp kingside_attacked?(game, opponent, :white) do
    Game.attacked?(game, 60, opponent) or Game.attacked?(game, 61, opponent) or
      Game.attacked?(game, 62, opponent)
  end

  defp kingside_attacked?(game, opponent, :black) do
    Game.attacked?(game, 4, opponent) or Game.attacked?(game, 5, opponent) or
      Game.attacked?(game, 6, opponent)
  end

  defp queenside_attacked?(game, opponent, :white) do
    Game.attacked?(game, 60, opponent) or Game.attacked?(game, 59, opponent) or
      Game.attacked?(game, 58, opponent)
  end

  defp queenside_attacked?(game, opponent, :black) do
    Game.attacked?(game, 4, opponent) or Game.attacked?(game, 3, opponent) or
      Game.attacked?(game, 2, opponent)
  end

  defp legal?(game, move) do
    next_game = Echecs.Game.make_move(game, move)

    king_color = game.turn

    king_pos = next_game.king_pos[king_color]

    if king_pos do
      not Echecs.Game.attacked?(next_game, king_pos, Echecs.Piece.opponent(king_color))
    else
      false
    end
  end
end
