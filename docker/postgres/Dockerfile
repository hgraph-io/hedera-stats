FROM postgres:16

# Build deps for timestamp9 (compiled from source) and runtime utilities
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    postgresql-server-dev-16 \
    postgresql-16-cron \
    postgresql-16-http \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install timestamp9 extension (nanosecond timestamp support for Hedera)
RUN curl -fsSL https://github.com/optiver/timestamp9/archive/refs/heads/master.tar.gz \
    -o /tmp/timestamp9.tar.gz \
    && tar -xzf /tmp/timestamp9.tar.gz -C /tmp \
    && cd /tmp/timestamp9-master \
    && mkdir build && cd build \
    && cmake .. \
    && make \
    && make install \
    && rm -rf /tmp/timestamp9*
