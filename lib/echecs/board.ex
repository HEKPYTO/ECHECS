defmodule Echecs.Board do
  @moduledoc """
  Represents a chess board using a 64-element tuple.
  Each element is `nil` (empty) or `{color, type}`.
  Indices are 0-63, representing squares a8 (0) to h1 (63).
  """

  alias Echecs.Piece

  @type square :: 0..63
  @type piece :: Piece.t()
  @type t :: tuple()

  def new do
    Tuple.duplicate(nil, 64)
  end

  @spec at(t(), square()) :: piece() | nil
  def at(board, index) when index in 0..63 do
    elem(board, index)
  end

  def at(_, _), do: nil

  @spec put(t(), square(), piece() | nil) :: t()
  def put(board, index, piece) when index in 0..63 do
    put_elem(board, index, piece)
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
end
