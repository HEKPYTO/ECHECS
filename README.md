# Echecs

A robust Chess Engine implemented in Elixir.

## Features

- **Move Generation**: Complete pseudo-legal and legal move generation.
- **FEN Handling**: Full Forsyth-Edwards Notation parsing and generation.
- **PGN Support**: Basic PGN parsing and move replay.
- **Game State**: Complete game state management including castling, en passant, half-move clock, and repetition detection.
- **Check/Checkmate/Stalemate Detection**: Accurate game termination logic.

## Prerequisites

- **Elixir**: 1.16 or later.
- **zstd**: Required for running the integration tests on compressed Lichess database files.

## Installation

To use `echecs` in your project, add it to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:echecs, "~> 0.1.0"}
  ]
end
```

## Quick Start

Start a new game and generate legal moves:

```elixir
# Start a new game with the standard opening position
game = Echecs.new_game()

# Get a list of all legal moves (returns Echecs.Move structs)
legal_moves = Echecs.legal_moves(game)
# => [%Echecs.Move{from: 8, to: 16, ...}, ...]

# Make a move (e.g., e2 to e4)
# Note: Squares are 0-indexed (a1=0, h1=7, ..., h8=63)
# e2 is 12, e4 is 28
case Echecs.make_move(game, 12, 28) do
  {:ok, new_game} -> 
    IO.puts "Move successful!"
    new_game
  {:error, reason} -> 
    IO.puts "Illegal move: #{reason}"
end

# Check game status
Echecs.status(game)
# => :active (or :checkmate, :stalemate, :draw)
```

### Working with FEN Strings

You can initialize a game from a FEN string or export the current state:

```elixir
# Initialize from FEN
fen = "rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq c6 0 2"
game = Echecs.new_game(fen)

# Export back to FEN
Echecs.FEN.to_string(game)
# => "rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq c6 0 2"
```

## Running Tests

### Unit Tests
Run the core test suite:
```bash
mix test
```

### Integration Tests (Lichess DB)
Test the engine against millions of real-world games from the Lichess database.
1. Download a zstd-compressed PGN file (e.g., `lichess_db_standard_rated_2016-06.pgn.zst`) and place it in the project root.
2. Run the integration test:

```bash
mix test --include integration test/integration/lichess_db_test.exs
```
*Note: The integration test defaults to processing a sample of 1,000,000 games. You can customize this by setting the `SAMPLE_SIZE` environment variable.*

## Docker Usage

For a consistent environment or to deploy the engine, you can use the Docker image.

### Pull from Registry
Pre-built images are available on GitHub Container Registry:
```bash
docker pull ghcr.io/hekpyto/echecs:latest
```

### Build the Image
```bash
docker build -t echecs .
```

### Run Interactive Shell
Launch an `iex` session with the `Echecs` library preloaded:
```bash
docker run -it --rm echecs
```
From here, you can interact with the API:
```elixir
iex> Echecs.new_game()
#Echecs.Game<...>
```

### Run Tests in Docker
To run the test suite within the container (useful for CI/CD consistency):
```bash
docker run --rm -v $(pwd):/app -w /app echecs mix test
```
*Note: This mounts your local source code into the container.*

## Linting

This project uses `Credo` for static code analysis. To run the linter:

```bash
mix credo --strict
```

## Documentation

Generate HTML documentation using `ExDoc`:

```bash
mix docs
```
The docs will be available in `doc/index.html`.
