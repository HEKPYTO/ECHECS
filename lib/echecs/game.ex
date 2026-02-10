defmodule Echecs.Game do
  @moduledoc """
  Holds the complete state of a chess game.
  """

  alias Echecs.Bitboard.Helper
  alias Echecs.{Board, FEN, Move, MoveGen, Piece}
  import Bitwise

  @type castling_side :: :kingside | :queenside
  @type castling_rights :: %{white: [castling_side()], black: [castling_side()]}

  @type t :: %__MODULE__{
          board: Board.t(),
          turn: Piece.color(),
          castling: castling_rights(),
          en_passant: Board.square() | nil,
          halfmove: non_neg_integer(),
          fullmove: pos_integer(),
          history: [any()],
          zobrist_hash: non_neg_integer(),
          king_pos: %{white: Board.square() | nil, black: Board.square() | nil}
        }

  defstruct board: Board.new(),
            turn: :white,
            castling: %{white: [:kingside, :queenside], black: [:kingside, :queenside]},
            en_passant: nil,
            halfmove: 0,
            fullmove: 1,
            history: [],
            zobrist_hash: 0,
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

    new_hash =
      Echecs.Zobrist.update_hash(
        game.zobrist_hash,
        move,
        piece,
        target_piece,
        {game.castling, castling},
        {game.en_passant, en_passant},
        game.turn
      )

    %__MODULE__{
      game
      | board: board,
        turn: next_turn,
        castling: castling,
        en_passant: en_passant,
        halfmove: halfmove,
        fullmove: fullmove,
        history: [game.zobrist_hash | game.history],
        zobrist_hash: new_hash,
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

  defp castling_rook_move(:kingside_castle, :white), do: {63, 61}
  defp castling_rook_move(:queenside_castle, :white), do: {56, 59}
  defp castling_rook_move(:kingside_castle, :black), do: {7, 5}
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
    Board.attacked?(game.board, sq, attacker_color)
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
    current_hash = game.zobrist_hash

    Enum.count(game.history, &(&1 == current_hash)) >= 2
  end

  defp insufficient_material?(game) do
    board = game.board
    all_pieces = board.all_pieces
    count = Helper.pop_count(all_pieces)

    cond do
      count == 2 ->
        true

      count == 3 ->
        majors =
          board.white_rooks ||| board.white_queens ||| board.white_pawns |||
            board.black_rooks ||| board.black_queens ||| board.black_pawns

        majors == 0

      count == 4 ->
        others =
          board.white_rooks ||| board.white_queens ||| board.white_pawns ||| board.white_knights |||
            board.black_rooks ||| board.black_queens ||| board.black_pawns ||| board.black_knights

        if others == 0 do
          check_bishops_same_color(board)
        else
          false
        end

      true ->
        false
    end
  end

  defp check_bishops_same_color(board) do
    if Helper.pop_count(board.white_bishops) == 1 and
         Helper.pop_count(board.black_bishops) == 1 do
      w_bishop_sq = Helper.lsb(board.white_bishops)
      b_bishop_sq = Helper.lsb(board.black_bishops)

      wc = square_color(w_bishop_sq)
      bc = square_color(b_bishop_sq)

      wc == bc
    else
      false
    end
  end

  defp square_color(idx) do
    rank = div(idx, 8)
    file = rem(idx, 8)
    rem(rank + file, 2)
  end
end
