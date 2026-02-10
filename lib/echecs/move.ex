defmodule Echecs.Move do
  @moduledoc """
  Represents a chess move.
  """

  import Bitwise

  @type t :: %__MODULE__{
          from: Echecs.Board.square(),
          to: Echecs.Board.square(),
          promotion: Echecs.Piece.type() | nil,
          special: :kingside_castle | :queenside_castle | :en_passant | nil
        }

  defstruct [:from, :to, :promotion, :special]

  @compile {:inline, decode_promo: 1, decode_special: 1, encode_promo: 1, encode_special: 1}

  defmacro pack(from, to, promotion, special) do
    quote do
      unquote(from) |||
        unquote(to) <<< 6 |||
        Echecs.Move.encode_promo(unquote(promotion)) <<< 12 |||
        Echecs.Move.encode_special(unquote(special)) <<< 15
    end
  end

  defmacro unpack_from(int), do: quote(do: unquote(int) &&& 0x3F)
  defmacro unpack_to(int), do: quote(do: unquote(int) >>> 6 &&& 0x3F)

  defmacro unpack_promotion(int) do
    quote do
      Echecs.Move.decode_promo(unquote(int) >>> 12 &&& 0x7)
    end
  end

  defmacro unpack_special(int) do
    quote do
      Echecs.Move.decode_special(unquote(int) >>> 15 &&& 0x7)
    end
  end

  def encode_promo(nil), do: 0
  def encode_promo(:knight), do: 1
  def encode_promo(:bishop), do: 2
  def encode_promo(:rook), do: 3
  def encode_promo(:queen), do: 4

  def decode_promo(0), do: nil
  def decode_promo(1), do: :knight
  def decode_promo(2), do: :bishop
  def decode_promo(3), do: :rook
  def decode_promo(4), do: :queen
  def decode_promo(_), do: nil

  def encode_special(nil), do: 0
  def encode_special(:en_passant), do: 1
  def encode_special(:kingside_castle), do: 2
  def encode_special(:queenside_castle), do: 3

  def decode_special(0), do: nil
  def decode_special(1), do: :en_passant
  def decode_special(2), do: :kingside_castle
  def decode_special(3), do: :queenside_castle
  def decode_special(_), do: nil

  def new(from, to, promotion \\ nil, special \\ nil) do
    %__MODULE__{
      from: from,
      to: to,
      promotion: promotion,
      special: special
    }
  end

  def to_struct(int) do
    %__MODULE__{
      from: unpack_from(int),
      to: unpack_to(int),
      promotion: unpack_promotion(int),
      special: unpack_special(int)
    }
  end
end
