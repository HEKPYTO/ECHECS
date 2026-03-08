defmodule Echecs.Game do
  @moduledoc """
  Holds the complete state of a chess game.
  """

  import Bitwise

  alias Echecs.Bitboard.Helper
  alias Echecs.{Board, FEN, Move, MoveGen, Piece, Zobrist}

  require Echecs.Move

  @wk 1
  @wq 2
  @bk 4
  @bq 8

  @castling_masks (for sq <- 0..63 do
                     cond do
                       sq == 0 -> 15 - @bq
                       sq == 4 -> 15 - @bk - @bq
                       sq == 7 -> 15 - @bk
                       sq == 56 -> 15 - @wq
                       sq == 60 -> 15 - @wk - @wq
                       sq == 63 -> 15 - @wk
                       true -> 15
                     end
                   end)
                  |> List.to_tuple()

  @type king_pos :: {Board.square() | nil, Board.square() | nil}

  @type t :: %__MODULE__{
          board: Board.board_tuple(),
          turn: Piece.color(),
          castling: non_neg_integer(),
          en_passant: Board.square() | nil,
          halfmove: non_neg_integer(),
          fullmove: pos_integer(),
          history: [non_neg_integer()],
          zobrist_hash: non_neg_integer(),
          king_pos: king_pos()
        }

  defstruct board: nil,
            turn: :white,
            castling: 15,
            en_passant: nil,
            halfmove: 0,
            fullmove: 1,
            history: [],
            zobrist_hash: 0,
            king_pos: {60, 4}

  @start_fen "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

  @doc """
  Creates a new game from a FEN string.
  """
  @spec new(String.t()) :: t()
  def new(fen \\ @start_fen) do
    parsed = FEN.parse(fen)
    board = ensure_tuple(parsed.board)
    king_pos = king_positions(board)
    zobrist_hash = Zobrist.hash(board, parsed.turn, parsed.castling, parsed.en_passant)

    struct(
      __MODULE__,
      Map.merge(parsed, %{
        board: board,
        history: [zobrist_hash],
        king_pos: king_pos,
        zobrist_hash: zobrist_hash
      })
    )
  end

  @doc """
  Executes a move on the game state.
  """
  @spec make_move(t(), Move.t()) :: t()
  def make_move(%__MODULE__{} = game, %Move{} = move) do
    make_move_int(game, Move.pack(move.from, move.to, move.promotion, move.special))
  end

  @doc """
  Executes a packed move on the game state.
  """
  @spec make_move_int(t(), integer()) :: t()
  def make_move_int(%__MODULE__{} = game, packed_move) when is_integer(packed_move) do
    game
    |> advance_state_from_game(packed_move)
    |> build_game(game, true)
  end

  @doc """
  Executes a packed move using the canonical transition pipeline without extending history.
  """
  @spec make_move_perft(t(), integer()) :: t()
  def make_move_perft(%__MODULE__{} = game, packed_move) when is_integer(packed_move) do
    game
    |> advance_state_from_game(packed_move)
    |> build_game(game, false)
  end

  @doc """
  Verifies if a pseudo-legal move leaves the mover in check.
  """
  @spec verify_move(t(), Move.t()) :: boolean()
  def verify_move(%__MODULE__{} = game, %Move{} = move) do
    verify_move_int(game, Move.pack(move.from, move.to, move.promotion, move.special))
  end

  @doc """
  Returns true if a packed pseudo-legal move is legal.
  """
  @spec verify_move_int(t(), integer()) :: boolean()
  def verify_move_int(%__MODULE__{} = game, packed_move) when is_integer(packed_move) do
    {new_board, _new_turn, _new_castling, _new_ep, new_king_pos} =
      advance_position(
        game.board,
        game.turn,
        game.castling,
        game.en_passant,
        game.king_pos,
        packed_move
      )

    mover_color = game.turn
    king_sq = king_sq_for(new_king_pos, mover_color)

    not is_nil(king_sq) and not Board.attacked?(new_board, king_sq, Piece.opponent(mover_color))
  end

  @doc """
  Returns true if the current side to move is in check.
  """
  @spec in_check?(t()) :: boolean()
  def in_check?(%__MODULE__{} = game) do
    king_sq = king_sq_for(game.king_pos, game.turn) || find_king_sq(game.board, game.turn)
    not is_nil(king_sq) and Board.attacked?(game.board, king_sq, Piece.opponent(game.turn))
  end

  @doc """
  Returns true if the game is over by checkmate.
  """
  @spec checkmate?(t()) :: boolean()
  def checkmate?(%__MODULE__{} = game) do
    in_check?(game) and not MoveGen.has_legal_move?(game)
  end

  @doc """
  Returns true if the game is over by stalemate.
  """
  @spec stalemate?(t()) :: boolean()
  def stalemate?(%__MODULE__{} = game) do
    not in_check?(game) and not MoveGen.has_legal_move?(game)
  end

  @doc """
  Returns true if the game is drawn.
  """
  @spec draw?(t()) :: boolean()
  def draw?(%__MODULE__{} = game) do
    game.halfmove >= 100 or repetition?(game) or insufficient_material?(game)
  end

  @doc """
  Returns true if the given castling right is present.
  """
  @spec has_right?(non_neg_integer(), Piece.color(), :kingside | :queenside) :: boolean()
  @compile {:inline, has_right?: 3, king_sq_for: 2}
  def has_right?(castling, :white, :kingside), do: (castling &&& @wk) != 0
  def has_right?(castling, :white, :queenside), do: (castling &&& @wq) != 0
  def has_right?(castling, :black, :kingside), do: (castling &&& @bk) != 0
  def has_right?(castling, :black, :queenside), do: (castling &&& @bq) != 0

  @doc false
  @spec castling_masks() :: tuple()
  def castling_masks, do: @castling_masks

  @doc false
  @spec king_positions(Board.board_tuple() | Board.t()) :: king_pos()
  def king_positions(board) do
    board = ensure_tuple(board)
    {find_king_sq(board, :white), find_king_sq(board, :black)}
  end

  @doc false
  @spec attacked?(t(), Board.square(), Piece.color()) :: boolean()
  def attacked?(%__MODULE__{} = game, sq, attacker_color) do
    Board.attacked?(game.board, sq, attacker_color)
  end

  @doc false
  @spec advance_state(
          {Board.board_tuple(), Piece.color(), non_neg_integer(), Board.square() | nil,
           non_neg_integer(), pos_integer(), king_pos(), non_neg_integer()},
          integer()
        ) ::
          {Board.board_tuple(), Piece.color(), non_neg_integer(), Board.square() | nil,
           non_neg_integer(), pos_integer(), king_pos(), non_neg_integer()}
  def advance_state(
        {board, turn, castling, en_passant, halfmove, fullmove, king_pos, zobrist_hash},
        packed_move
      ) do
    {new_board, new_turn, new_castling, new_en_passant, new_king_pos, piece, target_piece, from,
     to, promotion, special} =
      advance_state_fields(board, turn, castling, king_pos, packed_move)

    new_halfmove = update_halfmove(halfmove, piece, target_piece)
    new_fullmove = if turn == :black, do: fullmove + 1, else: fullmove

    new_hash =
      Zobrist.update_hash_int(
        zobrist_hash,
        from,
        to,
        promotion,
        special,
        piece,
        target_piece,
        {castling, new_castling},
        {en_passant, new_en_passant},
        turn
      )

    {new_board, new_turn, new_castling, new_en_passant, new_halfmove, new_fullmove, new_king_pos,
     new_hash}
  end

  @doc false
  @spec advance_position(
          Board.board_tuple(),
          Piece.color(),
          non_neg_integer(),
          Board.square() | nil,
          king_pos(),
          integer()
        ) ::
          {Board.board_tuple(), Piece.color(), non_neg_integer(), Board.square() | nil,
           king_pos()}
  def advance_position(board, turn, castling, _en_passant, king_pos, packed_move) do
    from = Move.unpack_from(packed_move)
    to = Move.unpack_to(packed_move)
    piece = Board.at_tuple(board, from)
    advance_position_fields(board, turn, castling, king_pos, packed_move, from, to, piece)
  end

  defp advance_state_from_game(%__MODULE__{} = game, packed_move) do
    advance_state(
      {game.board, game.turn, game.castling, game.en_passant, game.halfmove, game.fullmove,
       game.king_pos, game.zobrist_hash},
      packed_move
    )
  end

  defp build_game(
         {board, turn, castling, en_passant, halfmove, fullmove, king_pos, zobrist_hash},
         %__MODULE__{} = game,
         track_history?
       ) do
    %__MODULE__{
      game
      | board: board,
        turn: turn,
        castling: castling,
        en_passant: en_passant,
        halfmove: halfmove,
        fullmove: fullmove,
        history: history_for(track_history?, game.history, zobrist_hash),
        zobrist_hash: zobrist_hash,
        king_pos: king_pos
    }
  end

  defp history_for(true, history, zobrist_hash), do: [zobrist_hash | history]
  defp history_for(false, history, _zobrist_hash), do: history

  defp update_halfmove(_, {_, :pawn}, _), do: 0
  defp update_halfmove(_, _, target) when not is_nil(target), do: 0
  defp update_halfmove(current, _, _), do: current + 1

  defp update_king_pos(king_pos, {_, :king}, to, :white), do: put_elem(king_pos, 0, to)
  defp update_king_pos(king_pos, {_, :king}, to, :black), do: put_elem(king_pos, 1, to)
  defp update_king_pos(king_pos, _, _, _), do: king_pos

  defp repetition?(%__MODULE__{} = game) do
    game.history
    |> Enum.take(game.halfmove + 1)
    |> count_matches(game.zobrist_hash, 0)
  end

  defp count_matches(_, _hash, 3), do: true
  defp count_matches([], _hash, _count), do: false

  defp count_matches([hash | rest], target_hash, count) do
    next_count = if hash == target_hash, do: count + 1, else: count
    count_matches(rest, target_hash, next_count)
  end

  defp insufficient_material?(%__MODULE__{board: board}) do
    count = Helper.pop_count(Board.all_occ(board))

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

        others == 0 and bishops_same_color?(board)

      true ->
        false
    end
  end

  defp bishops_same_color?(board) do
    white_bishops = Board.wb(board)
    black_bishops = Board.bb(board)

    if Helper.pop_count(white_bishops) == 1 and Helper.pop_count(black_bishops) == 1 do
      square_color(Helper.lsb(white_bishops)) == square_color(Helper.lsb(black_bishops))
    else
      false
    end
  end

  defp square_color(idx), do: rem(div(idx, 8) + rem(idx, 8), 2)

  defp advance_state_fields(board, turn, castling, king_pos, packed_move) do
    from = Move.unpack_from(packed_move)
    to = Move.unpack_to(packed_move)
    promotion = Move.unpack_promotion(packed_move)
    special = Move.unpack_special(packed_move)
    piece = Board.at_tuple(board, from)
    target_piece = Board.at_tuple(board, to)

    {new_board, new_turn, new_castling, new_en_passant, new_king_pos} =
      advance_position_fields(board, turn, castling, king_pos, packed_move, from, to, piece)

    {new_board, new_turn, new_castling, new_en_passant, new_king_pos, piece, target_piece, from,
     to, promotion, special}
  end

  defp advance_position_fields(board, turn, castling, king_pos, packed_move, from, to, piece) do
    new_board = Board.make_move_on_board_tuple(board, packed_move, turn)
    new_turn = Piece.opponent(turn)
    new_castling = castling &&& elem(@castling_masks, from) &&& elem(@castling_masks, to)
    new_en_passant = calculate_en_passant(piece, from, to)
    new_king_pos = update_king_pos(king_pos, piece, to, turn)
    {new_board, new_turn, new_castling, new_en_passant, new_king_pos}
  end

  defp calculate_en_passant({_, :pawn}, from, to) when abs(from - to) == 16 do
    div(from + to, 2)
  end

  defp calculate_en_passant(_, _, _), do: nil

  defp king_sq_for(king_pos, :white), do: elem(king_pos, 0)
  defp king_sq_for(king_pos, :black), do: elem(king_pos, 1)

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
end
