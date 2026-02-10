import Config

if Mix.env() == :dev do
  config :git_hooks,
    auto_install: true,
    verbose: true,
    hooks: [
      pre_commit: [
        tasks: [
          {:cmd, "mix format --check-formatted"},
          {:cmd, "mix credo --strict"},
          {:cmd, "mix test --exclude integration --exclude comparison"}
        ]
      ]
    ]
end
