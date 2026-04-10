FROM postgres:16

RUN apt-get update && apt-get install -y \
    build-essential \
    postgresql-server-dev-16 \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install timestamp9 extension (nanosecond timestamp support for Hedera)
RUN git clone https://github.com/optiver/timestamp9.git /tmp/timestamp9 \
    && cd /tmp/timestamp9 \
    && make \
    && make install \
    && rm -rf /tmp/timestamp9
