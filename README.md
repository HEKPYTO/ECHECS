# Echecs

**A pure Elixir chess library focused on rule correctness and practical performance.**

[![CI](https://github.com/HEKPYTO/ECHECS/actions/workflows/ci.yml/badge.svg)](https://github.com/HEKPYTO/ECHECS/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/echecs.svg)](https://hex.pm/packages/echecs)

Echecs is a chess library implemented entirely in Elixir. It aims to keep the public API straightforward while using a faster internal representation for move generation, legality checks, and perft-style traversal.

Internally, the engine uses bitboards, packed integer moves, precomputed attack tables, and a tuple-based board representation. Those choices keep the hot path compact on the BEAM without relying on NIFs or external native code.

## Features

*   **Pure Elixir**: core move generation and rule handling stay in Elixir.
*   **Bitboard-based engine**: board state is tracked with 64-bit piece sets and precomputed attack tables.
*   **Packed move format**: internal move generation uses integers to reduce allocation in tight loops.
*   **Standard chess support**: legal move generation, FEN, PGN replay, castling, en passant, promotion, repetition, and the 50-move rule.
*   **Benchmarkable internals**: the repository includes perft and move generation benchmarks for regression tracking.

## How It Works

The public interface centers on `%Echecs.Game{}`. That struct keeps the information needed for normal application use such as turn, castling rights, en passant state, clocks, and game history.

For engine work, the board is converted into an internal tuple of bitboards. Move generation operates on that tuple representation and uses precomputed attack data for kings, knights, pawns, and magic-bitboard lookups for sliding pieces.

Moves are represented internally as packed integers. That allows legality checks and perft traversal to stay on a lightweight path before moves are converted back into structs for the higher-level API.

Repetition detection and state transitions use Zobrist hashing so positions can be tracked efficiently without comparing full board states on every move.

## Installation

Add `echecs` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:echecs, "~> 0.1.4"}
  ]
end
```

## Quick Start

### Basic Game Loop

```elixir
game = Echecs.new_game()

moves = Echecs.legal_moves(game)

from = Echecs.Board.to_index("e2")
to = Echecs.Board.to_index("e4")
{:ok, game} = Echecs.make_move(game, from, to)

Echecs.status(game)
```

Squares are 0-indexed from `a8 = 0` through `h1 = 63`.

### FEN Manipulation

```elixir
game = Echecs.new_game("rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq c6 0 2")

Echecs.FEN.to_string(game)
```

### PGN Parsing

```elixir
pgn = "1. e4 e5 2. Nf3 Nc6 3. Bb5"
moves = Echecs.PGN.parse_moves(pgn)
final_game = Echecs.PGN.replay(Echecs.new_game(), moves)
```

## Advanced Usage

### Performance Considerations

`Echecs.MoveGen.legal_moves_int/1` returns packed integer moves instead of structs. That is the lower-level API used by the faster internal paths and is useful when you need to iterate over many positions without extra allocation.

### Internal Board Representation

The board is represented internally as a tuple of bitboards. This keeps access and updates inexpensive on the BEAM and matches the data layout used by the move generator and perft code.

## Testing & Benchmarks

The engine is verified against large-scale replay validation from the Lichess database to ensure correctness and stability.

### Run Unit Tests
```bash
mix test
```

### Run Integration Benchmark
To verify large-scale replay correctness on your machine:

```bash
LICHESS_DB_PATH=path/to/file.pgn.zst mix test --include integration test/integration/lichess_db_test.exs
```

### Run Engine Benchmarks
```bash
mix echecs.benchmark
```

### Regenerate the Magic Cache
```bash
elixir scripts/generate_magic_cache.exs
```

## Docker Support

Deploy or test in a consistent environment using the provided Docker image. The image automatically pre-generates the magic bitboard cache for faster startup.

```bash
docker build -t echecs .

docker run -it --rm echecs
iex> Echecs.new_game()
```
