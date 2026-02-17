defmodule Echecs.Board do
  @moduledoc """
  Represents a chess board using Bitboards.
  """

  import Bitwise
  require Echecs.Bitboard.Constants
  alias Echecs.Bitboard.{Constants, Magic, Precomputed}

  @mask64 0xFFFFFFFFFFFFFFFF

  # 0: white_pawns, 1: white_knights, 2: white_bishops, 3: white_rooks, 4: white_queens, 5: white_king
  # 6: black_pawns, 7: black_knights, 8: black_bishops, 9: black_rooks, 10: black_queens, 11: black_king
  # 12: white_pieces, 13: black_pieces, 14: all_pieces

  @type board_tuple :: {
          integer(),
          integer(),
          integer(),
          integer(),
          integer(),
          integer(),
          integer(),
          integer(),
          integer(),
          integer(),
          integer(),
          integer(),
          integer(),
          integer(),
          integer()
        }

  # Helper to access tuple elements by index
  @compile {:inline,
            wp: 1,
            wn: 1,
            wb: 1,
            wr: 1,
            wq: 1,
            wk: 1,
            bp: 1,
            bn: 1,
            bb: 1,
            br: 1,
            bq: 1,
            bk: 1,
            white_occ: 1,
            black_occ: 1,
            all_occ: 1,
            at_tuple: 2}

  def wp(board), do: elem(board, 0)
  def wn(board), do: elem(board, 1)
  def wb(board), do: elem(board, 2)
  def wr(board), do: elem(board, 3)
  def wq(board), do: elem(board, 4)
  def wk(board), do: elem(board, 5)
  def bp(board), do: elem(board, 6)
  def bn(board), do: elem(board, 7)
  def bb(board), do: elem(board, 8)
  def br(board), do: elem(board, 9)
  def bq(board), do: elem(board, 10)
  def bk(board), do: elem(board, 11)
  def white_occ(board), do: elem(board, 12)
  def black_occ(board), do: elem(board, 13)
  def all_occ(board), do: elem(board, 14)

  @doc """
  Fast piece lookup on a tuple board. Returns {color, type} or nil.
  """
  def at_tuple(board, index) do
    mask = 1 <<< index

    if (elem(board, 14) &&& mask) == 0 do
      nil
    else
      if (elem(board, 12) &&& mask) != 0 do
        find_white_piece_tuple(board, mask)
      else
        find_black_piece_tuple(board, mask)
      end
    end
  end

  defp find_white_piece_tuple(board, mask) do
    cond do
      (elem(board, 0) &&& mask) != 0 -> {:white, :pawn}
      (elem(board, 1) &&& mask) != 0 -> {:white, :knight}
      (elem(board, 2) &&& mask) != 0 -> {:white, :bishop}
      (elem(board, 3) &&& mask) != 0 -> {:white, :rook}
      (elem(board, 4) &&& mask) != 0 -> {:white, :queen}
      (elem(board, 5) &&& mask) != 0 -> {:white, :king}
      true -> nil
    end
  end

  defp find_black_piece_tuple(board, mask) do
    cond do
      (elem(board, 6) &&& mask) != 0 -> {:black, :pawn}
      (elem(board, 7) &&& mask) != 0 -> {:black, :knight}
      (elem(board, 8) &&& mask) != 0 -> {:black, :bishop}
      (elem(board, 9) &&& mask) != 0 -> {:black, :rook}
      (elem(board, 10) &&& mask) != 0 -> {:black, :queen}
      (elem(board, 11) &&& mask) != 0 -> {:black, :king}
      true -> nil
    end
  end

  def new_tuple do
    # Initial board state as a tuple
    {
      Constants.rank_2(),
      0x42 <<< 56,
      0x24 <<< 56,
      0x81 <<< 56,
      0x08 <<< 56,
      0x10 <<< 56,
      Constants.rank_7(),
      0x42,
      0x24,
      0x81,
      0x08,
      0x10,
      0xFFFF <<< 48,
      0xFFFF,
      0xFFFF00000000FFFF
    }
  end

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

  def to_struct(tuple) do
    struct(
      __MODULE__,
      white_pawns: elem(tuple, 0),
      white_knights: elem(tuple, 1),
      white_bishops: elem(tuple, 2),
      white_rooks: elem(tuple, 3),
      white_queens: elem(tuple, 4),
      white_king: elem(tuple, 5),
      black_pawns: elem(tuple, 6),
      black_knights: elem(tuple, 7),
      black_bishops: elem(tuple, 8),
      black_rooks: elem(tuple, 9),
      black_queens: elem(tuple, 10),
      black_king: elem(tuple, 11),
      white_pieces: elem(tuple, 12),
      black_pieces: elem(tuple, 13),
      all_pieces: elem(tuple, 14)
    )
  end

  def from_struct(struct) do
    {
      struct.white_pawns,
      struct.white_knights,
      struct.white_bishops,
      struct.white_rooks,
      struct.white_queens,
      struct.white_king,
      struct.black_pawns,
      struct.black_knights,
      struct.black_bishops,
      struct.black_rooks,
      struct.black_queens,
      struct.black_king,
      struct.white_pieces,
      struct.black_pieces,
      struct.all_pieces
    }
  end

  @doc """
  Returns true if the square `sq` is attacked by `attacker_color`.
  Accepts both tuple and struct boards.
  """
  def attacked?(board, sq, attacker_color) when is_tuple(board) do
    non_sliding_attacked?(board, sq, attacker_color) or
      sliding_attacked?(board, sq, attacker_color)
  end

  def attacked?(board, sq, attacker_color) do
    attacked?(from_struct(board), sq, attacker_color)
  end

  require Echecs.Move

  defp non_sliding_attacked?(board, sq, attacker_color) do
    pawn_attacked?(board, sq, attacker_color) or
      knight_attacked?(board, sq, attacker_color) or
      king_attacked?(board, sq, attacker_color)
  end

  defp pawn_attacked?(board, sq, attacker_color) do
    defender_color = if attacker_color == :white, do: :black, else: :white
    pawn_mask = Precomputed.get_pawn_attacks(sq, defender_color)
    pawns = if attacker_color == :white, do: wp(board), else: bp(board)
    (pawn_mask &&& pawns) != 0
  end

  defp knight_attacked?(board, sq, attacker_color) do
    knight_mask = Precomputed.get_knight_attacks(sq)
    knights = if attacker_color == :white, do: wn(board), else: bn(board)
    (knight_mask &&& knights) != 0
  end

  defp king_attacked?(board, sq, attacker_color) do
    king_mask = Precomputed.get_king_attacks(sq)
    kings = if attacker_color == :white, do: wk(board), else: bk(board)
    (king_mask &&& kings) != 0
  end

  defp sliding_attacked?(board, sq, attacker_color) do
    bishop_mask = Magic.get_bishop_attacks(sq, all_occ(board))

    bishops_queens =
      if attacker_color == :white,
        do: wb(board) ||| wq(board),
        else: bb(board) ||| bq(board)

    diag_hit = (bishop_mask &&& bishops_queens) != 0

    if diag_hit do
      true
    else
      rook_mask = Magic.get_rook_attacks(sq, all_occ(board))

      rooks_queens =
        if attacker_color == :white,
          do: wr(board) ||| wq(board),
          else: br(board) ||| bq(board)

      (rook_mask &&& rooks_queens) != 0
    end
  end

  @doc """
  Applies a move to the bitboards only. Used for fast legality checking.
  Returns the updated board tuple. Single-write: destructures once, constructs one new tuple.
  """
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def make_move_on_board_tuple(board, move, turn) do
    from = Echecs.Move.unpack_from(move)
    to = Echecs.Move.unpack_to(move)
    promotion = Echecs.Move.unpack_promotion(move)
    special = Echecs.Move.unpack_special(move)

    from_mask = 1 <<< from
    to_mask = 1 <<< to

    {p0, p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11, w_occ, b_occ, _a_occ} = board

    # Determine mover's piece type index
    {mover_idx, _piece_type} = find_piece_idx_and_type(board, turn, from_mask)

    # 1. Apply mover update
    {p0, p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11} =
      if promotion do
        promo_idx = tuple_index(turn, promotion)
        pieces = {p0, p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11}
        # Clear piece from origin
        pieces =
          put_piece_elem(
            pieces,
            mover_idx,
            elem(pieces, mover_idx) &&& bnot(from_mask) &&& @mask64
          )

        # Set promoted piece at destination
        put_piece_elem(pieces, promo_idx, elem(pieces, promo_idx) ||| to_mask)
      else
        move_mask = from_mask ||| to_mask
        pieces = {p0, p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11}
        put_piece_elem(pieces, mover_idx, bxor(elem(pieces, mover_idx), move_mask))
      end

    # 2. Handle capture
    opp_occ = if turn == :white, do: b_occ, else: w_occ

    {p0, p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11, new_w, new_b} =
      cond do
        special == :en_passant ->
          cap_mask = if turn == :white, do: 1 <<< (to + 8), else: 1 <<< (to - 8)
          cap_idx = if turn == :white, do: 6, else: 0
          pieces = {p0, p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11}

          {cp0, cp1, cp2, cp3, cp4, cp5, cp6, cp7, cp8, cp9, cp10, cp11} =
            put_piece_elem(pieces, cap_idx, elem(pieces, cap_idx) &&& bnot(cap_mask) &&& @mask64)

          # Incremental: mover XOR from+to, opponent clear cap_mask
          if turn == :white do
            {cp0, cp1, cp2, cp3, cp4, cp5, cp6, cp7, cp8, cp9, cp10, cp11,
             bxor(w_occ, from_mask ||| to_mask), b_occ &&& bnot(cap_mask) &&& @mask64}
          else
            {cp0, cp1, cp2, cp3, cp4, cp5, cp6, cp7, cp8, cp9, cp10, cp11,
             w_occ &&& bnot(cap_mask) &&& @mask64, bxor(b_occ, from_mask ||| to_mask)}
          end

        (opp_occ &&& to_mask) != 0 ->
          # Standard capture: find and clear the captured piece
          opp_start = if turn == :white, do: 6, else: 0
          pieces = {p0, p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11}
          clear_mask = bnot(to_mask) &&& @mask64

          {cp0, cp1, cp2, cp3, cp4, cp5, cp6, cp7, cp8, cp9, cp10, cp11} =
            clear_captured_piece(pieces, opp_start, to_mask, clear_mask)

          # Mover: XOR from, set to (= XOR from, OR to works since we own to after capture)
          # Opponent: clear to
          if turn == :white do
            {cp0, cp1, cp2, cp3, cp4, cp5, cp6, cp7, cp8, cp9, cp10, cp11,
             bxor(w_occ, from_mask) ||| to_mask, b_occ &&& clear_mask}
          else
            {cp0, cp1, cp2, cp3, cp4, cp5, cp6, cp7, cp8, cp9, cp10, cp11, w_occ &&& clear_mask,
             bxor(b_occ, from_mask) ||| to_mask}
          end

        true ->
          # Quiet move: just XOR from+to on mover's occupancy
          move_mask = from_mask ||| to_mask

          if turn == :white do
            {p0, p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11, bxor(w_occ, move_mask), b_occ}
          else
            {p0, p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11, w_occ, bxor(b_occ, move_mask)}
          end
      end

    # 3. Handle castling rook
    {p0, p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11, new_w, new_b} =
      case special do
        :kingside_castle ->
          {r_from, r_to} = if turn == :white, do: {63, 61}, else: {7, 5}
          r_mask = 1 <<< r_from ||| 1 <<< r_to
          rook_idx = if turn == :white, do: 3, else: 9
          pieces = {p0, p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11}

          {rp0, rp1, rp2, rp3, rp4, rp5, rp6, rp7, rp8, rp9, rp10, rp11} =
            put_piece_elem(pieces, rook_idx, bxor(elem(pieces, rook_idx), r_mask))

          occ =
            if turn == :white,
              do: {bxor(new_w, r_mask), new_b},
              else: {new_w, bxor(new_b, r_mask)}

          {rp0, rp1, rp2, rp3, rp4, rp5, rp6, rp7, rp8, rp9, rp10, rp11, elem(occ, 0),
           elem(occ, 1)}

        :queenside_castle ->
          {r_from, r_to} = if turn == :white, do: {56, 59}, else: {0, 3}
          r_mask = 1 <<< r_from ||| 1 <<< r_to
          rook_idx = if turn == :white, do: 3, else: 9
          pieces = {p0, p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11}

          {rp0, rp1, rp2, rp3, rp4, rp5, rp6, rp7, rp8, rp9, rp10, rp11} =
            put_piece_elem(pieces, rook_idx, bxor(elem(pieces, rook_idx), r_mask))

          occ =
            if turn == :white,
              do: {bxor(new_w, r_mask), new_b},
              else: {new_w, bxor(new_b, r_mask)}

          {rp0, rp1, rp2, rp3, rp4, rp5, rp6, rp7, rp8, rp9, rp10, rp11, elem(occ, 0),
           elem(occ, 1)}

        _ ->
          {p0, p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11, new_w, new_b}
      end

    {p0, p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11, new_w, new_b, new_w ||| new_b}
  end

  # Returns {index, piece_type} for the piece at from_mask
  @compile {:inline, find_piece_idx_and_type: 3}
  defp find_piece_idx_and_type(board, :white, mask) do
    cond do
      (elem(board, 0) &&& mask) != 0 -> {0, :pawn}
      (elem(board, 1) &&& mask) != 0 -> {1, :knight}
      (elem(board, 2) &&& mask) != 0 -> {2, :bishop}
      (elem(board, 3) &&& mask) != 0 -> {3, :rook}
      (elem(board, 4) &&& mask) != 0 -> {4, :queen}
      (elem(board, 5) &&& mask) != 0 -> {5, :king}
    end
  end

  defp find_piece_idx_and_type(board, :black, mask) do
    cond do
      (elem(board, 6) &&& mask) != 0 -> {6, :pawn}
      (elem(board, 7) &&& mask) != 0 -> {7, :knight}
      (elem(board, 8) &&& mask) != 0 -> {8, :bishop}
      (elem(board, 9) &&& mask) != 0 -> {9, :rook}
      (elem(board, 10) &&& mask) != 0 -> {10, :queen}
      (elem(board, 11) &&& mask) != 0 -> {11, :king}
    end
  end

  # Update a single element in a 12-element piece tuple
  @compile {:inline, put_piece_elem: 3}
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp put_piece_elem({e0, e1, e2, e3, e4, e5, e6, e7, e8, e9, e10, e11}, idx, val) do
    case idx do
      0 -> {val, e1, e2, e3, e4, e5, e6, e7, e8, e9, e10, e11}
      1 -> {e0, val, e2, e3, e4, e5, e6, e7, e8, e9, e10, e11}
      2 -> {e0, e1, val, e3, e4, e5, e6, e7, e8, e9, e10, e11}
      3 -> {e0, e1, e2, val, e4, e5, e6, e7, e8, e9, e10, e11}
      4 -> {e0, e1, e2, e3, val, e5, e6, e7, e8, e9, e10, e11}
      5 -> {e0, e1, e2, e3, e4, val, e6, e7, e8, e9, e10, e11}
      6 -> {e0, e1, e2, e3, e4, e5, val, e7, e8, e9, e10, e11}
      7 -> {e0, e1, e2, e3, e4, e5, e6, val, e8, e9, e10, e11}
      8 -> {e0, e1, e2, e3, e4, e5, e6, e7, val, e9, e10, e11}
      9 -> {e0, e1, e2, e3, e4, e5, e6, e7, e8, val, e10, e11}
      10 -> {e0, e1, e2, e3, e4, e5, e6, e7, e8, e9, val, e11}
      11 -> {e0, e1, e2, e3, e4, e5, e6, e7, e8, e9, e10, val}
    end
  end

  # Clear captured piece from opponent's bitboards
  @compile {:inline, clear_captured_piece: 4}
  defp clear_captured_piece(pieces, start, to_mask, clear_mask) do
    cond do
      (elem(pieces, start) &&& to_mask) != 0 ->
        put_piece_elem(pieces, start, elem(pieces, start) &&& clear_mask)

      (elem(pieces, start + 1) &&& to_mask) != 0 ->
        put_piece_elem(pieces, start + 1, elem(pieces, start + 1) &&& clear_mask)

      (elem(pieces, start + 2) &&& to_mask) != 0 ->
        put_piece_elem(pieces, start + 2, elem(pieces, start + 2) &&& clear_mask)

      (elem(pieces, start + 3) &&& to_mask) != 0 ->
        put_piece_elem(pieces, start + 3, elem(pieces, start + 3) &&& clear_mask)

      (elem(pieces, start + 4) &&& to_mask) != 0 ->
        put_piece_elem(pieces, start + 4, elem(pieces, start + 4) &&& clear_mask)

      true ->
        pieces
    end
  end

  defp tuple_index(:white, :knight), do: 1
  defp tuple_index(:white, :bishop), do: 2
  defp tuple_index(:white, :rook), do: 3
  defp tuple_index(:white, :queen), do: 4
  defp tuple_index(:black, :knight), do: 7
  defp tuple_index(:black, :bishop), do: 8
  defp tuple_index(:black, :rook), do: 9
  defp tuple_index(:black, :queen), do: 10

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

  @spec at(t() | board_tuple(), square()) :: piece()
  def at(board, index) when is_tuple(board) and index in 0..63 do
    at_tuple(board, index)
  end

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
