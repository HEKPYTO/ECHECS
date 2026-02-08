defmodule Echecs.Move do
  @moduledoc """
  Represents a chess move.
  """

  @type t :: %__MODULE__{
          from: Echecs.Board.square(),
          to: Echecs.Board.square(),
          promotion: Echecs.Piece.type() | nil,
          special: :kingside_castle | :queenside_castle | :en_passant | nil
        }

  defstruct [:from, :to, :promotion, :special]

  def new(from, to, promotion \\ nil, special \\ nil) do
    %__MODULE__{
      from: from,
      to: to,
      promotion: promotion,
      special: special
    }
  end
end
