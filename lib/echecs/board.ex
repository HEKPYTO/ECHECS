defmodule Echecs.Board do
  @moduledoc """
  Represents a chess board using Bitboards.
  """

  import Bitwise
  require Echecs.Bitboard.Constants
  alias Echecs.Bitboard.{Constants, Magic, Precomputed}

  defstruct white_pawns: 0,
            white_knights: 0,
            white_bishops: 0,
            white_rooks: 0,
            white_queens: 0,
            white_king: 0,
            black_pawns: 0,
            black_knights: 0,
            black_bishops: 0,
            black_rooks: 0,
            black_queens: 0,
            black_king: 0,
            white_pieces: 0,
            black_pieces: 0,
            all_pieces: 0

  @type t :: %__MODULE__{}
  @type square :: 0..63
  @type piece :: {atom(), atom()} | nil

  def new do
    %__MODULE__{}
    |> set_initial_pieces()
    |> update_aggregates()
  end

  @doc """
  Returns true if the square `sq` is attacked by `attacker_color`.
  """
  def attacked?(board, sq, attacker_color) do
    non_sliding_attacked?(board, sq, attacker_color) or
      sliding_attacked?(board, sq, attacker_color)
  end

  defp non_sliding_attacked?(board, sq, attacker_color) do
    pawn_attacked?(board, sq, attacker_color) or
      knight_attacked?(board, sq, attacker_color) or
      king_attacked?(board, sq, attacker_color)
  end

  defp pawn_attacked?(board, sq, attacker_color) do
    defender_color = if attacker_color == :white, do: :black, else: :white
    pawn_mask = Precomputed.get_pawn_attacks(sq, defender_color)
    pawns = if attacker_color == :white, do: board.white_pawns, else: board.black_pawns
    (pawn_mask &&& pawns) != 0
  end

  defp knight_attacked?(board, sq, attacker_color) do
    knight_mask = Precomputed.get_knight_attacks(sq)
    knights = if attacker_color == :white, do: board.white_knights, else: board.black_knights
    (knight_mask &&& knights) != 0
  end

  defp king_attacked?(board, sq, attacker_color) do
    king_mask = Precomputed.get_king_attacks(sq)
    kings = if attacker_color == :white, do: board.white_king, else: board.black_king
    (king_mask &&& kings) != 0
  end

  defp sliding_attacked?(board, sq, attacker_color) do
    bishop_mask = Magic.get_bishop_attacks(sq, board.all_pieces)

    bishops_queens =
      if attacker_color == :white,
        do: board.white_bishops ||| board.white_queens,
        else: board.black_bishops ||| board.black_queens

    diag_hit = (bishop_mask &&& bishops_queens) != 0

    if diag_hit do
      true
    else
      rook_mask = Magic.get_rook_attacks(sq, board.all_pieces)

      rooks_queens =
        if attacker_color == :white,
          do: board.white_rooks ||| board.white_queens,
          else: board.black_rooks ||| board.black_queens

      (rook_mask &&& rooks_queens) != 0
    end
  end

  require Echecs.Move

  @doc """
  Applies a move to the bitboards only. Used for fast legality checking.
  Returns the updated board struct.
  """
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def make_move_on_bitboards(board, move, turn) do
    from = Echecs.Move.unpack_from(move)
    to = Echecs.Move.unpack_to(move)
    promotion = Echecs.Move.unpack_promotion(move)
    special = Echecs.Move.unpack_special(move)

    from_mask = 1 <<< from
    to_mask = 1 <<< to
    piece_type = find_piece_type_at_mask(board, turn, from_mask)

    board =
      if promotion do
        board
        |> update_bb_mask(turn, piece_type, from_mask, :clear)
        |> update_bb_mask(turn, promotion, to_mask, :set)
      else
        move_mask = from_mask ||| to_mask
        update_bb_mask(board, turn, piece_type, move_mask, :xor)
      end

    opponent = if turn == :white, do: :black, else: :white

    board =
      cond do
        special == :en_passant ->
          cap_sq = if turn == :white, do: to + 8, else: to - 8
          update_bb_mask(board, opponent, :pawn, 1 <<< cap_sq, :clear)

        (board.all_pieces &&& to_mask) != 0 ->
          captured_type = find_piece_type_at_mask(board, opponent, to_mask)

          if captured_type do
            update_bb_mask(board, opponent, captured_type, to_mask, :clear)
          else
            board
          end

        true ->
          board
      end

    board =
      if special in [:kingside_castle, :queenside_castle] do
        {r_from, r_to} =
          case {special, turn} do
            {:kingside_castle, :white} -> {63, 61}
            {:queenside_castle, :white} -> {56, 59}
            {:kingside_castle, :black} -> {7, 5}
            {:queenside_castle, :black} -> {0, 3}
          end

        r_mask = 1 <<< r_from ||| 1 <<< r_to
        update_bb_mask(board, turn, :rook, r_mask, :xor)
      else
        board
      end

    update_aggregates(board)
  end

  defp set_initial_pieces(board) do
    %{
      board
      | white_pawns: Constants.rank_2(),
        white_rooks: 0x81 <<< 56,
        white_knights: 0x42 <<< 56,
        white_bishops: 0x24 <<< 56,
        white_queens: 0x08 <<< 56,
        white_king: 0x10 <<< 56,
        black_pawns: Constants.rank_7(),
        black_rooks: 0x81,
        black_knights: 0x42,
        black_bishops: 0x24,
        black_queens: 0x08,
        black_king: 0x10
    }
  end

  def from_tuple(mailbox) when is_tuple(mailbox) and tuple_size(mailbox) == 64 do
    initial = %__MODULE__{}

    0..63
    |> Enum.reduce(initial, fn idx, board ->
      case elem(mailbox, idx) do
        nil -> board
        piece -> add_piece_bb(board, idx, piece)
      end
    end)
    |> update_aggregates()
  end

  @spec at(t(), square()) :: piece()
  def at(board, index) when index in 0..63 do
    mask = 1 <<< index

    if (board.all_pieces &&& mask) == 0 do
      nil
    else
      find_piece_at_fast(board, mask)
    end
  end

  def at(_, _), do: nil

  defp find_piece_at_fast(board, mask) do
    cond do
      (board.white_pieces &&& mask) != 0 -> find_white_piece_at_mask(board, mask)
      (board.black_pieces &&& mask) != 0 -> find_black_piece_at_mask(board, mask)
      true -> nil
    end
  end

  defp find_white_piece_at_mask(board, mask) do
    cond do
      (board.white_pawns &&& mask) != 0 -> {:white, :pawn}
      (board.white_knights &&& mask) != 0 -> {:white, :knight}
      (board.white_bishops &&& mask) != 0 -> {:white, :bishop}
      (board.white_rooks &&& mask) != 0 -> {:white, :rook}
      (board.white_queens &&& mask) != 0 -> {:white, :queen}
      (board.white_king &&& mask) != 0 -> {:white, :king}
      true -> nil
    end
  end

  defp find_black_piece_at_mask(board, mask) do
    cond do
      (board.black_pawns &&& mask) != 0 -> {:black, :pawn}
      (board.black_knights &&& mask) != 0 -> {:black, :knight}
      (board.black_bishops &&& mask) != 0 -> {:black, :bishop}
      (board.black_rooks &&& mask) != 0 -> {:black, :rook}
      (board.black_queens &&& mask) != 0 -> {:black, :queen}
      (board.black_king &&& mask) != 0 -> {:black, :king}
      true -> nil
    end
  end

  @spec put(t(), square(), piece()) :: t()
  def put(board, index, piece) when index in 0..63 do
    board =
      if (board.all_pieces &&& 1 <<< index) != 0 do
        type = find_piece_at_fast(board, 1 <<< index)
        remove_piece_bb(board, index, type)
      else
        board
      end

    board = if piece, do: add_piece_bb(board, index, piece), else: board

    update_aggregates(board)
  end

  def move_bitboards(board, from, to, piece_type, piece_color, capture_type, promotion_type) do
    board = update_bb_mask(board, piece_color, piece_type, 1 <<< from, :clear)
    board = handle_capture(board, capture_type, piece_color, to)

    final_type = promotion_type || piece_type
    board = update_bb_mask(board, piece_color, final_type, 1 <<< to, :set)

    board = handle_castling(board, capture_type, piece_color)

    update_aggregates(board)
  end

  defp handle_capture(board, nil, _, _), do: board

  defp handle_capture(board, capture_type, piece_color, to) do
    opponent = if piece_color == :white, do: :black, else: :white

    capture_sq =
      if capture_type == :en_passant do
        if piece_color == :white, do: to + 8, else: to - 8
      else
        to
      end

    captured_piece_type = find_piece_type_at_mask(board, opponent, 1 <<< capture_sq)

    if captured_piece_type do
      update_bb_mask(board, opponent, captured_piece_type, 1 <<< capture_sq, :clear)
    else
      board
    end
  end

  defp handle_castling(board, :kingside_castle, piece_color) do
    {r_from, r_to} = if piece_color == :white, do: {63, 61}, else: {7, 5}

    board
    |> update_bb_mask(piece_color, :rook, 1 <<< r_from, :clear)
    |> update_bb_mask(piece_color, :rook, 1 <<< r_to, :set)
  end

  defp handle_castling(board, :queenside_castle, piece_color) do
    {r_from, r_to} = if piece_color == :white, do: {56, 59}, else: {0, 3}

    board
    |> update_bb_mask(piece_color, :rook, 1 <<< r_from, :clear)
    |> update_bb_mask(piece_color, :rook, 1 <<< r_to, :set)
  end

  defp handle_castling(board, _, _), do: board

  defp find_piece_type_at_mask(board, :white, mask) do
    cond do
      (board.white_pawns &&& mask) != 0 -> :pawn
      (board.white_knights &&& mask) != 0 -> :knight
      (board.white_bishops &&& mask) != 0 -> :bishop
      (board.white_rooks &&& mask) != 0 -> :rook
      (board.white_queens &&& mask) != 0 -> :queen
      (board.white_king &&& mask) != 0 -> :king
      true -> nil
    end
  end

  defp find_piece_type_at_mask(board, :black, mask) do
    cond do
      (board.black_pawns &&& mask) != 0 -> :pawn
      (board.black_knights &&& mask) != 0 -> :knight
      (board.black_bishops &&& mask) != 0 -> :bishop
      (board.black_rooks &&& mask) != 0 -> :rook
      (board.black_queens &&& mask) != 0 -> :queen
      (board.black_king &&& mask) != 0 -> :king
      true -> nil
    end
  end

  def to_index(sq_str) do
    <<file::utf8, rank::utf8>> = sq_str
    col = file - ?a
    row = ?8 - rank
    row * 8 + col
  end

  def to_algebraic(index) do
    row = div(index, 8)
    col = rem(index, 8)
    rank = ?8 - row
    file = ?a + col
    List.to_string([file, rank])
  end

  defp update_bb_mask(board, :white, :pawn, mask, op),
    do: %{board | white_pawns: apply_op(board.white_pawns, mask, op)}

  defp update_bb_mask(board, :white, :knight, mask, op),
    do: %{board | white_knights: apply_op(board.white_knights, mask, op)}

  defp update_bb_mask(board, :white, :bishop, mask, op),
    do: %{board | white_bishops: apply_op(board.white_bishops, mask, op)}

  defp update_bb_mask(board, :white, :rook, mask, op),
    do: %{board | white_rooks: apply_op(board.white_rooks, mask, op)}

  defp update_bb_mask(board, :white, :queen, mask, op),
    do: %{board | white_queens: apply_op(board.white_queens, mask, op)}

  defp update_bb_mask(board, :white, :king, mask, op),
    do: %{board | white_king: apply_op(board.white_king, mask, op)}

  defp update_bb_mask(board, :black, :pawn, mask, op),
    do: %{board | black_pawns: apply_op(board.black_pawns, mask, op)}

  defp update_bb_mask(board, :black, :knight, mask, op),
    do: %{board | black_knights: apply_op(board.black_knights, mask, op)}

  defp update_bb_mask(board, :black, :bishop, mask, op),
    do: %{board | black_bishops: apply_op(board.black_bishops, mask, op)}

  defp update_bb_mask(board, :black, :rook, mask, op),
    do: %{board | black_rooks: apply_op(board.black_rooks, mask, op)}

  defp update_bb_mask(board, :black, :queen, mask, op),
    do: %{board | black_queens: apply_op(board.black_queens, mask, op)}

  defp update_bb_mask(board, :black, :king, mask, op),
    do: %{board | black_king: apply_op(board.black_king, mask, op)}

  defp apply_op(val, mask, :set), do: val ||| mask
  defp apply_op(val, mask, :clear), do: val &&& bnot(mask)
  defp apply_op(val, mask, :xor), do: bxor(val, mask)

  defp add_piece_bb(board, index, {color, type}) do
    update_bb_mask(board, color, type, 1 <<< index, :set)
  end

  defp remove_piece_bb(board, index, {color, type}) do
    update_bb_mask(board, color, type, 1 <<< index, :clear)
  end

  defp update_aggregates(board) do
    white =
      board.white_pawns ||| board.white_knights ||| board.white_bishops |||
        board.white_rooks ||| board.white_queens ||| board.white_king

    black =
      board.black_pawns ||| board.black_knights ||| board.black_bishops |||
        board.black_rooks ||| board.black_queens ||| board.black_king

    %{board | white_pieces: white, black_pieces: black, all_pieces: white ||| black}
  end
end
