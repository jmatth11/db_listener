# build step
FROM alpine:latest AS builder

RUN apk update && \
    apk add clang \
      cmake \
      git \
      wget

RUN mkdir -p /app
RUN mkdir -p /tmp/zig
RUN wget -O /tmp/zig/zig.tar.xz  "https://ziglang.org/download/0.15.2/zig-x86_64-linux-0.15.2.tar.xz"
RUN tar -xf /tmp/zig/zig.tar.xz -C /tmp/zig/
WORKDIR /app
COPY . /app
RUN /tmp/zig/zig-x86_64-linux-0.15.2/zig build -Doptimize=ReleaseSafe
# clone simple web front-end
RUN mkdir /app/web
RUN git clone https://github.com/jmatth11/db_listener_web.git /app/web

# Run step
FROM alpine:latest AS runtime
ARG SERVER_PORT=3000
COPY --from=builder /app/zig-out/bin/db_listener /db_listener
COPY --from=builder /app/web /web

ENV WEB_DIR=/web
ENV SERVER_PORT=${SERVER_PORT}

EXPOSE ${SERVER_PORT}

ENTRYPOINT ["/db_listener"]
