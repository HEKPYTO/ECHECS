defmodule Echecs.Game do
  @moduledoc """
  Holds the complete state of a chess game.
  """

  alias Echecs.{Board, FEN, Move, MoveGen, Piece}

  @type castling_side :: :kingside | :queenside
  @type castling_rights :: %{white: [castling_side()], black: [castling_side()]}

  @type t :: %__MODULE__{
          board: Board.t(),
          turn: Piece.color(),
          castling: castling_rights(),
          en_passant: Board.square() | nil,
          halfmove: non_neg_integer(),
          fullmove: pos_integer(),
          # Can be hash or struct
          history: [any()],
          king_pos: %{white: Board.square() | nil, black: Board.square() | nil}
        }

  defstruct board: Board.new(),
            turn: :white,
            castling: %{white: [:kingside, :queenside], black: [:kingside, :queenside]},
            en_passant: nil,
            halfmove: 0,
            fullmove: 1,
            history: [],
            king_pos: %{white: 60, black: 4}

  @start_fen "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

  @doc """
  Creates a new game from a FEN string (defaults to starting position).
  """
  @spec new(String.t()) :: t()
  def new(fen \\ @start_fen) do
    parsed = FEN.parse(fen)

    king_pos = %{
      white: find_king_scan(parsed.board, :white),
      black: find_king_scan(parsed.board, :black)
    }

    initial_state = {parsed.board, parsed.turn, parsed.castling, parsed.en_passant}

    struct(__MODULE__, Map.merge(parsed, %{history: [initial_state], king_pos: king_pos}))
  end

  defp find_king_scan(board, color) do
    0..63
    |> Enum.find(fn i -> Board.at(board, i) == {color, :king} end)
  end

  @doc """
  Executes a move on the game state. 
  Assumes the move is pseudo-legal (does not check validity).
  Used for 'make_move' and legal move verification.
  """
  def make_move(%__MODULE__{} = game, %Move{} = move) do
    piece = Board.at(game.board, move.from)
    target_piece = Board.at(game.board, move.to)

    board = apply_move_to_board(game.board, move, piece, game.turn)
    next_turn = Piece.opponent(game.turn)
    castling = update_castling_rights(game.castling, piece, move.from, target_piece, move.to)
    en_passant = calculate_en_passant(piece, move)
    halfmove = update_halfmove(game.halfmove, piece, target_piece)
    fullmove = if game.turn == :black, do: game.fullmove + 1, else: game.fullmove
    king_pos = update_king_pos(game.king_pos, piece, move.to, game.turn)

    state_hash = {board, next_turn, castling, en_passant}

    %__MODULE__{
      game
      | board: board,
        turn: next_turn,
        castling: castling,
        en_passant: en_passant,
        halfmove: halfmove,
        fullmove: fullmove,
        history: [state_hash | game.history],
        king_pos: king_pos
    }
  end

  defp apply_move_to_board(board, move, piece, turn) do
    board =
      board
      |> Board.put(move.from, nil)
      |> Board.put(move.to, update_piece(piece, move))

    cond do
      move.special == :en_passant ->
        capture_idx = if turn == :white, do: move.to + 8, else: move.to - 8
        Board.put(board, capture_idx, nil)

      move.special in [:kingside_castle, :queenside_castle] ->
        {rook_from, rook_to} = castling_rook_move(move.special, turn)
        rook = Board.at(board, rook_from)

        board
        |> Board.put(rook_from, nil)
        |> Board.put(rook_to, rook)

      true ->
        board
    end
  end

  defp calculate_en_passant({_, :pawn}, %Move{from: from, to: to}) when abs(from - to) == 16 do
    div(from + to, 2)
  end

  defp calculate_en_passant(_, _), do: nil

  defp update_halfmove(_, {_, :pawn}, _), do: 0
  defp update_halfmove(_, _, target) when not is_nil(target), do: 0
  defp update_halfmove(current, _, _), do: current + 1

  defp update_king_pos(king_pos, {_, :king}, to, turn) do
    Map.put(king_pos, turn, to)
  end

  defp update_king_pos(king_pos, _, _, _), do: king_pos

  defp update_piece({color, :pawn}, %Move{promotion: type}) when not is_nil(type) do
    {color, type}
  end

  defp update_piece(piece, _), do: piece

  # h1 -> f1
  defp castling_rook_move(:kingside_castle, :white), do: {63, 61}
  # a1 -> d1
  defp castling_rook_move(:queenside_castle, :white), do: {56, 59}
  # h8 -> f8
  defp castling_rook_move(:kingside_castle, :black), do: {7, 5}
  # a8 -> d8
  defp castling_rook_move(:queenside_castle, :black), do: {0, 3}

  defp update_castling_rights(castling, {color, type}, from, target_piece, to) do
    castling
    |> update_rights_for_mover(color, type, from)
    |> update_rights_for_capture(target_piece, to)
  end

  defp update_rights_for_mover(castling, color, :king, _) do
    Map.put(castling, color, [])
  end

  defp update_rights_for_mover(castling, color, :rook, from) do
    remove_right_for_square(castling, color, from)
  end

  defp update_rights_for_mover(castling, _, _, _), do: castling

  defp update_rights_for_capture(castling, nil, _), do: castling

  defp update_rights_for_capture(castling, {captured_color, :rook}, to) do
    remove_right_for_square(castling, captured_color, to)
  end

  defp update_rights_for_capture(castling, _, _), do: castling

  defp remove_right_for_square(castling, :white, 63),
    do: remove_right(castling, :white, :kingside)

  defp remove_right_for_square(castling, :white, 56),
    do: remove_right(castling, :white, :queenside)

  defp remove_right_for_square(castling, :black, 7), do: remove_right(castling, :black, :kingside)

  defp remove_right_for_square(castling, :black, 0),
    do: remove_right(castling, :black, :queenside)

  defp remove_right_for_square(castling, _, _), do: castling

  defp remove_right(castling, color, side) do
    rights = Map.get(castling, color, [])
    Map.put(castling, color, List.delete(rights, side))
  end

  @doc """
  Verifies if a move is legal without generating all other legal moves.
  Assumes the move is pseudo-legal (valid piece moves).
  Checks if the move leaves the king in check.
  """
  def verify_move(game, move) do
    next_game = make_move(game, move)

    mover_color = game.turn

    king_pos = next_game.king_pos[mover_color]

    if king_pos do
      not attacked?(next_game, king_pos, Piece.opponent(mover_color))
    else
      false
    end
  end

  @doc """
  Returns true if the current side to move is in check.
  """
  def in_check?(game) do
    king_pos = game.king_pos[game.turn] || find_king_scan(game.board, game.turn)
    attacked?(game, king_pos, Piece.opponent(game.turn))
  end

  def attacked?(game, sq, attacker_color) do
    knight_attacks?(game.board, sq, attacker_color) or
      sliding_attacks?(game.board, sq, attacker_color) or
      pawn_attacks?(game.board, sq, attacker_color) or
      king_attacks?(game.board, sq, attacker_color)
  end

  defp knight_attacks?(board, sq, color) do
    offsets = [-17, -15, -10, -6, 6, 10, 15, 17]

    Enum.any?(offsets, fn offset ->
      target = sq + offset

      target in 0..63 and
        check_piece(board, target, color, :knight) and
        knight_jump?(sq, target)
    end)
  end

  defp knight_jump?(sq1, sq2) do
    abs(div(sq1, 8) - div(sq2, 8)) + abs(rem(sq1, 8) - rem(sq2, 8)) == 3
  end

  defp sliding_attacks?(board, sq, color) do
    slide_check(board, sq, [-8, -1, 1, 8], color, [:rook, :queen]) or
      slide_check(board, sq, [-9, -7, 7, 9], color, [:bishop, :queen])
  end

  defp slide_check(board, start, offsets, color, types) do
    Enum.any?(offsets, fn offset ->
      check_direction(board, start, offset, color, types)
    end)
  end

  defp check_direction(board, start, offset, color, types) do
    Stream.iterate(start + offset, &(&1 + offset))
    |> Stream.take_while(fn idx ->
      idx in 0..63 and abs(rem(idx, 8) - rem(idx - offset, 8)) <= 1
    end)
    |> Enum.reduce_while(false, &check_square(&1, &2, board, color, types))
  end

  defp check_square(idx, _, board, color, types) do
    case Board.at(board, idx) do
      nil ->
        {:cont, false}

      {^color, type} ->
        if type in types, do: {:halt, true}, else: {:halt, false}

      _ ->
        {:halt, false}
    end
  end

  defp pawn_attacks?(board, sq, color) do
    offsets = if color == :white, do: [7, 9], else: [-9, -7]

    Enum.any?(offsets, fn offset ->
      target = sq + offset

      target in 0..63 and
        abs(rem(sq, 8) - rem(target, 8)) == 1 and
        check_piece(board, target, color, :pawn)
    end)
  end

  defp king_attacks?(board, sq, color) do
    offsets = [-9, -8, -7, -1, 1, 7, 8, 9]

    Enum.any?(offsets, fn offset ->
      target = sq + offset

      target in 0..63 and
        abs(rem(sq, 8) - rem(target, 8)) <= 1 and
        check_piece(board, target, color, :king)
    end)
  end

  defp check_piece(board, idx, color, type) do
    case Board.at(board, idx) do
      {^color, ^type} -> true
      _ -> false
    end
  end

  @doc """
  Returns true if the game is over by checkmate.
  """
  def checkmate?(game) do
    in_check?(game) and no_legal_moves?(game)
  end

  @doc """
  Returns true if the game is over by stalemate.
  """
  def stalemate?(game) do
    not in_check?(game) and no_legal_moves?(game)
  end

  defp no_legal_moves?(game) do
    MoveGen.legal_moves(game) == []
  end

  @doc """
  Returns true if the game is drawn by 50-move rule or repetition.
  """
  def draw?(game) do
    fifty_move_rule?(game) or repetition?(game) or insufficient_material?(game)
  end

  defp fifty_move_rule?(game), do: game.halfmove >= 100

  defp repetition?(game) do
    current_state = {game.board, game.turn, game.castling, game.en_passant}

    count = Enum.count(game.history, fn state -> state == current_state end)
    count >= 3
  end

  defp insufficient_material?(game) do
    pieces =
      game.board
      |> Tuple.to_list()
      |> Enum.with_index()
      |> Enum.reject(fn {p, _} -> is_nil(p) end)
      |> Enum.map(fn {{c, t}, i} -> {c, t, i} end)

    count = length(pieces)

    cond do
      count == 2 ->
        true

      count == 3 ->
        Enum.any?(pieces, fn {_, t, _} -> t in [:bishop, :knight] end)

      count == 4 ->
        bishops = Enum.filter(pieces, fn {_, t, _} -> t == :bishop end)

        if length(bishops) == 2 do
          [{c1, _, i1}, {c2, _, i2}] = bishops

          c1 != c2 and square_color(i1) == square_color(i2)
        else
          false
        end

      true ->
        false
    end
  end

  defp square_color(idx) do
    rank = div(idx, 8)
    file = rem(idx, 8)
    rem(rank + file, 2)
  end
end
