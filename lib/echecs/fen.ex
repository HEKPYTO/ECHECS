defmodule Echecs.FEN do
  @moduledoc """
  Handles parsing and generation of Forsyth-Edwards Notation (FEN) strings.
  """

  alias Echecs.{Board, Piece}
  import Bitwise

  @type fen :: String.t()

  @doc """
  Parses a FEN string into its components.
  """
  @spec parse(fen()) :: map()
  def parse(fen) do
    [placement, turn, castling, ep, half, full] = String.split(fen, " ")

    %{
      board: parse_placement(placement),
      turn: parse_turn(turn),
      castling: parse_castling(castling),
      en_passant: parse_en_passant(ep),
      halfmove: String.to_integer(half),
      fullmove: String.to_integer(full)
    }
  end

  defp parse_placement(placement) do
    rows = String.split(placement, "/")

    rows
    |> Enum.flat_map(&parse_row/1)
    |> List.to_tuple()
    |> Board.from_tuple()
  end

  defp parse_row(row) do
    String.to_charlist(row)
    |> Enum.flat_map(fn char ->
      if char in ?1..?8 do
        List.duplicate(nil, char - ?0)
      else
        [Piece.from_char(char)]
      end
    end)
  end

  defp parse_turn("w"), do: :white
  defp parse_turn("b"), do: :black

  # Castling rights as 4-bit integer
  # Bit 0 (1): White Kingside
  # Bit 1 (2): White Queenside
  # Bit 2 (4): Black Kingside
  # Bit 3 (8): Black Queenside
  defp parse_castling("-"), do: 0

  defp parse_castling(str) do
    r = 0
    r = if String.contains?(str, "K"), do: r ||| 1, else: r
    r = if String.contains?(str, "Q"), do: r ||| 2, else: r
    r = if String.contains?(str, "k"), do: r ||| 4, else: r
    if String.contains?(str, "q"), do: r ||| 8, else: r
  end

  defp parse_en_passant("-"), do: nil
  defp parse_en_passant(sq), do: Board.to_index(sq)

  @doc """
  Generates a FEN string from game components.
  """
  def to_string(game) do
    placement = generate_placement(game.board)
    turn = if game.turn == :white, do: "w", else: "b"
    castling = generate_castling(game.castling)
    ep = if game.en_passant, do: Board.to_algebraic(game.en_passant), else: "-"

    "#{placement} #{turn} #{castling} #{ep} #{game.halfmove} #{game.fullmove}"
  end

  defp generate_placement(board) do
    Enum.map_join(0..7, "/", fn row ->
      0..7
      |> Enum.map(fn col -> Board.at(board, row * 8 + col) end)
      |> row_to_fen()
    end)
  end

  defp row_to_fen(pieces) do
    pieces
    |> Enum.chunk_by(&is_nil/1)
    |> Enum.map_join(fn chunk ->
      if List.first(chunk) == nil do
        Integer.to_string(length(chunk))
      else
        List.to_string(Enum.map(chunk, &Piece.to_char/1))
      end
    end)
  end

  defp generate_castling(0), do: "-"

  defp generate_castling(rights) do
    res =
      if((rights &&& 1) != 0, do: "K", else: "") <>
        if((rights &&& 2) != 0, do: "Q", else: "") <>
        if((rights &&& 4) != 0, do: "k", else: "") <>
        if (rights &&& 8) != 0, do: "q", else: ""

    if res == "", do: "-", else: res
  end
end
