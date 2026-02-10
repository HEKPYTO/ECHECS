defmodule Echecs.Bitboard do
  @moduledoc """
  Core Bitboard implementation using 64-bit Integers.
  This represents the board state and provides optimized bitwise operations.
  """
  import Bitwise

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

  @rank_2 0x000000000000FF00
  @rank_7 0x00FF000000000000

  def new do
    %__MODULE__{}
    |> set_initial_pieces()
    |> update_aggregates()
  end

  defp set_initial_pieces(bb) do
    %{
      bb
      | white_pawns: @rank_2,
        white_rooks: 0x81,
        white_knights: 0x42,
        white_bishops: 0x24,
        white_queens: 0x08,
        white_king: 0x10,
        black_pawns: @rank_7,
        black_rooks: 0x81 <<< 56,
        black_knights: 0x42 <<< 56,
        black_bishops: 0x24 <<< 56,
        black_queens: 0x08 <<< 56,
        black_king: 0x10 <<< 56
    }
  end

  @doc "Updates the aggregate bitboards (white_pieces, black_pieces, all_pieces)"
  def update_aggregates(bb) do
    white =
      bb.white_pawns ||| bb.white_knights ||| bb.white_bishops ||| bb.white_rooks |||
        bb.white_queens ||| bb.white_king

    black =
      bb.black_pawns ||| bb.black_knights ||| bb.black_bishops ||| bb.black_rooks |||
        bb.black_queens ||| bb.black_king

    %{bb | white_pieces: white, black_pieces: black, all_pieces: white ||| black}
  end

  @doc "Returns the bitboard for a specific piece type and color"
  def get_piece_bb(bb, :white, :pawn), do: bb.white_pawns
  def get_piece_bb(bb, :white, :knight), do: bb.white_knights
  def get_piece_bb(bb, :white, :bishop), do: bb.white_bishops
  def get_piece_bb(bb, :white, :rook), do: bb.white_rooks
  def get_piece_bb(bb, :white, :queen), do: bb.white_queens
  def get_piece_bb(bb, :white, :king), do: bb.white_king
  def get_piece_bb(bb, :black, :pawn), do: bb.black_pawns
  def get_piece_bb(bb, :black, :knight), do: bb.black_knights
  def get_piece_bb(bb, :black, :bishop), do: bb.black_bishops
  def get_piece_bb(bb, :black, :rook), do: bb.black_rooks
  def get_piece_bb(bb, :black, :queen), do: bb.black_queens
  def get_piece_bb(bb, :black, :king), do: bb.black_king

  @doc "Returns true if bit at index is set"
  def occupied?(bb, index) when is_integer(bb), do: (bb &&& 1 <<< index) != 0

  @doc "Prints the bitboard for debugging"
  def print(bb) when is_integer(bb) do
    bb
    |> generate_board_string()
    |> IO.puts()
  end

  defp generate_board_string(bb) do
    7..0//-1
    |> Enum.map_join("\n", fn rank -> format_rank(bb, rank) end)
  end

  defp format_rank(bb, rank) do
    0..7
    |> Enum.map_join(" ", fn file ->
      sq = rank * 8 + file
      if occupied?(bb, sq), do: "X", else: "."
    end)
  end
end
