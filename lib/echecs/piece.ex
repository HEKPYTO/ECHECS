defmodule Echecs.Piece do
  @moduledoc """
  Defines chess piece types and colors.
  """

  @type color :: :white | :black
  @type type :: :pawn | :knight | :bishop | :rook | :queen | :king
  @type t :: {color(), type()}

  @colors [:white, :black]
  @types [:pawn, :knight, :bishop, :rook, :queen, :king]

  def colors, do: @colors
  def types, do: @types

  def opponent(:white), do: :black
  def opponent(:black), do: :white

  def from_char(char) do
    type = type_from_char(char)
    color = color_from_char(char)
    {color, type}
  end

  def type_from_char(char) when char in [?P, ?p], do: :pawn
  def type_from_char(char) when char in [?N, ?n], do: :knight
  def type_from_char(char) when char in [?B, ?b], do: :bishop
  def type_from_char(char) when char in [?R, ?r], do: :rook
  def type_from_char(char) when char in [?Q, ?q], do: :queen
  def type_from_char(char) when char in [?K, ?k], do: :king
  def type_from_char(_), do: nil

  def color_from_char(char) do
    if char in ?A..?Z, do: :white, else: :black
  end

  def to_char({color, type}) do
    char =
      case type do
        :pawn -> ?p
        :knight -> ?n
        :bishop -> ?b
        :rook -> ?r
        :queen -> ?q
        :king -> ?k
      end

    if color == :white, do: char - 32, else: char
  end
end
