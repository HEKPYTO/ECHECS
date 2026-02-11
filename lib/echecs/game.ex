defmodule Echecs.Game do
  @moduledoc """
  Holds the complete state of a chess game.
  """

  alias Echecs.Bitboard.Helper
  alias Echecs.{Board, FEN, Move, MoveGen, Piece}
  import Bitwise
  require Echecs.Move

  # Castling rights as 4-bit integer
  # Bit 0 (1): White Kingside
  # Bit 1 (2): White Queenside
  # Bit 2 (4): Black Kingside
  # Bit 3 (8): Black Queenside
  @wk 1
  @wq 2
  @bk 4
  @bq 8

  # Precomputed mask table for castling updates.
  # For each square, the mask of castling bits to KEEP when a piece moves from/to that square.
  # AND-ing castling with mask[from] & mask[to] handles both mover and capture in one step.
  @castling_masks (for sq <- 0..63 do
                     cond do
                       # a8: clear black queenside
                       sq == 0 -> 15 - @bq
                       # e8: clear both black
                       sq == 4 -> 15 - @bk - @bq
                       # h8: clear black kingside
                       sq == 7 -> 15 - @bk
                       # a1: clear white queenside
                       sq == 56 -> 15 - @wq
                       # e1: clear both white
                       sq == 60 -> 15 - @wk - @wq
                       # h1: clear white kingside
                       sq == 63 -> 15 - @wk
                       true -> 15
                     end
                   end)
                  |> List.to_tuple()

  @type t :: %__MODULE__{
          board: Board.board_tuple(),
          turn: Piece.color(),
          castling: non_neg_integer(),
          en_passant: Board.square() | nil,
          halfmove: non_neg_integer(),
          fullmove: pos_integer(),
          history: [any()],
          zobrist_hash: non_neg_integer(),
          king_pos: %{white: Board.square() | nil, black: Board.square() | nil}
        }

  defstruct board: nil,
            turn: :white,
            castling: 15,
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
    board = ensure_tuple(parsed.board)

    king_pos = %{
      white: find_king_sq(board, :white),
      black: find_king_sq(board, :black)
    }

    initial_state = {board, parsed.turn, parsed.castling, parsed.en_passant}

    struct(
      __MODULE__,
      Map.merge(parsed, %{board: board, history: [initial_state], king_pos: king_pos})
    )
  end

  defp find_king_sq(board, :white) do
    king_bb = Board.wk(board)
    if king_bb != 0, do: Helper.lsb(king_bb), else: nil
  end

  defp find_king_sq(board, :black) do
    king_bb = Board.bk(board)
    if king_bb != 0, do: Helper.lsb(king_bb), else: nil
  end

  defp ensure_tuple(board) when is_tuple(board), do: board
  defp ensure_tuple(board), do: Board.from_struct(board)

  @doc """
  Executes a move on the game state.
  Assumes the move is pseudo-legal (does not check validity).
  Used for 'make_move' and legal move verification.
  """
  def make_move(%__MODULE__{} = game, %Move{} = move) do
    board = game.board
    piece = Board.at_tuple(board, move.from)
    target_piece = Board.at_tuple(board, move.to)

    packed = Move.pack(move.from, move.to, move.promotion, move.special)
    new_board = Board.make_move_on_board_tuple(board, packed, game.turn)

    next_turn = Piece.opponent(game.turn)

    castling =
      game.castling &&& elem(@castling_masks, move.from) &&& elem(@castling_masks, move.to)

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
      | board: new_board,
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
    king_pos = game.king_pos[game.turn] || find_king_sq(game.board, game.turn)
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
    not MoveGen.has_legal_move?(game)
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

    # Only need to search back to the last irreversible move (halfmove clock)
    # and count 2-fold repetition (sufficient for playing)
    game.history
    |> Enum.take(game.halfmove)
    |> count_matches(current_hash, 0)
  end

  defp count_matches(_, _hash, 2), do: true
  defp count_matches([], _hash, _count), do: false

  defp count_matches([h | rest], hash, count) do
    count_matches(rest, hash, if(h == hash, do: count + 1, else: count))
  end

  defp insufficient_material?(game) do
    board = game.board
    all_pieces = Board.all_occ(board)
    count = Helper.pop_count(all_pieces)

    cond do
      count == 2 ->
        true

      count == 3 ->
        majors =
          Board.wr(board) ||| Board.wq(board) ||| Board.wp(board) |||
            Board.br(board) ||| Board.bq(board) ||| Board.bp(board)

        majors == 0

      count == 4 ->
        others =
          Board.wr(board) ||| Board.wq(board) ||| Board.wp(board) ||| Board.wn(board) |||
            Board.br(board) ||| Board.bq(board) ||| Board.bp(board) ||| Board.bn(board)

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
    wb = Board.wb(board)
    bb = Board.bb(board)

    if Helper.pop_count(wb) == 1 and Helper.pop_count(bb) == 1 do
      w_bishop_sq = Helper.lsb(wb)
      b_bishop_sq = Helper.lsb(bb)

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

  @compile {:inline, has_right?: 3}

  # Castling rights helpers (public for move_gen access)
  def has_right?(castling, :white, :kingside), do: (castling &&& @wk) != 0
  def has_right?(castling, :white, :queenside), do: (castling &&& @wq) != 0
  def has_right?(castling, :black, :kingside), do: (castling &&& @bk) != 0
  def has_right?(castling, :black, :queenside), do: (castling &&& @bq) != 0
end
