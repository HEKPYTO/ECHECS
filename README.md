# Echecs

**A high-performance Chess Engine implemented in pure Elixir.**

[![CI](https://github.com/HEKPYTO/ECHECS/actions/workflows/ci.yml/badge.svg)](https://github.com/HEKPYTO/ECHECS/actions/workflows/ci.yml)

Echecs is a robust chess library designed for speed and correctness. It leverages advanced optimization techniques available on the BEAM virtual machine, making it suitable for high-throughput analysis and scalable applications.

## Features

*   **High Performance**: Process over **4,000 games per second** (benchmarked on M1 Pro).
*   **Pure Elixir**: No NIFs or external dependencies (C/Rust) required for core logic.
*   **Advanced Engine Architecture**:
    *   **Bitboards**: 64-bit integer representation for O(1) board operations.
    *   **Magic Bitboards**: Fast sliding piece attack generation.
    *   **Integer Move Encoding**: Zero-allocation move generation using packed 20-bit integers to minimize Garbage Collection.
    *   **Zobrist Hashing**: Efficient game state hashing for repetition detection.
*   **Standard Compliance**:
    *   **FEN**: Full Forsyth-Edwards Notation parsing and generation.
    *   **PGN**: Parsing and replay support for standard chess games.
*   **Complete Rule Implementation**: Castling, En Passant, Promotion, 50-move rule, and 3-fold repetition.

## Installation

Add `echecs` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:echecs, "~> 0.1.3"}
  ]
end
```

## Changelog

### v0.1.3 (Phase 6 Optimization)
*   **Performance:** ~22% throughput increase (up to 4,100 games/sec).
*   **Zero-Allocation Legality Check:** Replaced struct-based move validation with optimized integer bitboard operations to eliminate GC pressure on the hot path.
*   **Tuple Board Representation:** Switched internal board state from Maps to Tuples for faster access and updates.
*   **Recursive Move Generation:** Replaced high-order functions with specialized recursive loops to reduce function call overhead.
*   **Inlining & Macro Optimization:** Critical bitwise helpers and constants are now inlined at compile time.
*   **Test Suite Overhaul:** Flattened test structure and added a comprehensive **Perft Suite** for rigorous correctness verification.

## Quick Start

### Basic Game Loop

```elixir
# Start a new game
game = Echecs.new_game()

# Generate legal moves
moves = Echecs.legal_moves(game)
# => [%Echecs.Move{from: 12, to: 28, ...}, ...]

# Make a move (e2 to e4)
# Squares are 0-indexed (a1=0 ... h8=63)
{:ok, game} = Echecs.make_move(game, 12, 28)

# Check game status
Echecs.status(game)
# => :active (or :checkmate, :stalemate, :draw)
```

### FEN Manipulation

```elixir
# Load specific position
game = Echecs.new_game("rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq c6 0 2")

# Export to FEN
Echecs.FEN.to_string(game)
```

## Testing & Benchmarks

The engine is verified against millions of real-world games from the Lichess database to ensure correctness and stability.

### Run Unit Tests
```bash
mix test
```

### Run Integration Benchmark
To verify performance on your machine:
1.  Download a [Lichess Database](https://database.lichess.org/) file (e.g., `lichess_db_standard_rated_2015-01.pgn.zst`).
2.  Run the integration test:

```bash
LICHESS_DB_PATH=path/to/file.pgn.zst mix test --include integration test/integration/lichess_db_test.exs
```

*Current Benchmark:* ~254s for 1,000,000 games (~3,924 games/sec).

## Docker Support

Deploy or test in a consistent environment using the provided Docker image.

```bash
# Build
docker build -t echecs .

# Run Interactive Shell
docker run -it --rm echecs
iex> Echecs.new_game()
```

## License

This project is licensed under the MIT License.
