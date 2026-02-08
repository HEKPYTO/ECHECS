# Configure ExUnit to exclude comparison and integration tests by default.
# - :comparison requires Node.js and external reference engine (dev/CI only)
# - :integration requires large external PGN files (CI/local only)
ExUnit.start(exclude: [:comparison, :integration])
