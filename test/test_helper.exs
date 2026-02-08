# Configure ExUnit to exclude comparison and integration tests by default.
# - :comparison requires Node.js and chess.js (dev/CI only)
# - :integration requires large external PGN files (CI/local only)
ExUnit.start(exclude: [:comparison, :integration])
