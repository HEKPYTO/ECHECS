FROM elixir:alpine AS builder

RUN apk add --no-cache build-base git

WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mix deps.compile

COPY lib lib
COPY scripts scripts
RUN elixir scripts/generate_magic_cache.exs
RUN mix compile

FROM elixir:alpine AS runner

RUN apk add --no-cache ncurses-libs zstd libstdc++

WORKDIR /app

RUN addgroup -g 1000 echecs && \
    adduser -u 1000 -G echecs -D echecs && \
    chown -R echecs:echecs /app

USER echecs

ENV MIX_ENV=prod \
    ERL_LIBS=/app/_build/prod/lib

COPY --from=builder --chown=echecs:echecs /app/_build/prod/lib ./_build/prod/lib

CMD ["iex"]
