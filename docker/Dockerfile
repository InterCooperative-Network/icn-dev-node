FROM rust:1.67-slim as builder

WORKDIR /build

# Install build dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        git \
        pkg-config \
        libssl-dev \
        build-essential \
        ca-certificates \
        && \
    rm -rf /var/lib/apt/lists/*

# Clone and build ICN repos
RUN git clone https://github.com/interchainio/icn-covm.git && \
    cd icn-covm && \
    cargo build --release

# ===== Runtime image =====
FROM debian:bullseye-slim

WORKDIR /app

# Install runtime dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        jq \
        && \
    rm -rf /var/lib/apt/lists/*

# Copy binaries from builder stage
COPY --from=builder /build/icn-covm/target/release/icn-node /usr/local/bin/

# Create data directory
RUN mkdir -p /data

# Copy entrypoint script
COPY entrypoint.sh /app/
RUN chmod +x /app/entrypoint.sh

VOLUME /data

EXPOSE 26656 26657 26660

ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["start", "--home", "/data"] 