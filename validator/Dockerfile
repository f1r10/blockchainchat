# ─── Stage 1: Build Rust Release Binary ─────────────────────────────────────────
FROM rust:1.80-slim-bookworm AS builder

WORKDIR /usr/src/app

# Install build dependencies required for compiling sled & crypto crates
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    pkg-config \
    libssl-dev \
    cmake \
    clang \
    && rm -rf /var/lib/apt/lists/*

# Copy root workspace files if present, or core + validator crates
COPY Cargo.toml ./
COPY core ./core
COPY validator ./validator

# Compile release binary for validator node
RUN cargo build --release --bin validator

# ─── Stage 2: Minimal Production Runtime ────────────────────────────────────────
FROM debian:bookworm-slim AS runtime

WORKDIR /app

# Install runtime dependencies & TLS certificates
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libssl3 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy compiled binary from builder
COPY --from=builder /usr/src/app/target/release/validator /usr/local/bin/validator

# Create data directory for persistent storage (sled DB)
RUN mkdir -p /data/mailbox_db && chmod 700 /data

# Default environment variables
ENV RUST_LOG=info
ENV MAILBOX_DB_PATH=/data/mailbox_db
ENV DHT_PORT=4001
ENV NYM_PORT=9000

# Expose libp2p DHT (TCP/UDP) & Nym Mixnet receiver (TCP)
EXPOSE 4001/tcp
EXPOSE 4001/udp
EXPOSE 9000/tcp

VOLUME ["/data"]

# Run the validator node binary
ENTRYPOINT ["/usr/local/bin/validator"]
