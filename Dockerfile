FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

# Install foundational build tools, runtimes, pandoc, xsltproc, beef, and postgresql
RUN apt-get update && apt-get install -y --no-install-recommends \
    software-properties-common \
    ca-certificates \
    curl \
    wget \
    git \
    build-essential \
    clang \
    llvm \
    make \
    python3 \
    python3-pip \
    pkg-config \
    libssl-dev \
    libxml2-utils \
    xsltproc \
    pandoc \
    postgresql \
    postgresql-contrib \
    postgresql-client \
    && add-apt-repository universe \
    && apt-get update \
    && apt-get install -y --no-install-recommends beef || true \
    && rm -rf /var/lib/apt/lists/*

# If beef package is unavailable on arm64/ubuntu 24.04, compile a lightweight C brainfuck interpreter as fallback/beef
RUN if ! command -v beef >/dev/null 2>&1; then \
      echo "Compiling beef/brainfuck interpreter fallback..." && \
      mkdir -p /tmp/bf && \
      printf '%s\n' \
        '#include <stdio.h>' \
        '#include <stdlib.h>' \
        'int main(int argc, char** argv) {' \
        '  if (argc < 2) return 1;' \
        '  FILE* f = fopen(argv[1], "rb");' \
        '  if (!f) return 1;' \
        '  fseek(f, 0, SEEK_END); long sz = ftell(f); fseek(f, 0, SEEK_SET);' \
        '  if (sz < 0) { fclose(f); return 1; }' \
        '  char* code = malloc(sz + 1);' \
        '  if (!code) { fclose(f); return 1; }' \
        '  size_t read_bytes = fread(code, 1, sz, f); code[read_bytes] = 0; fclose(f);' \
        '  unsigned char tape[65536] = {0}; int ptr = 0;' \
        '  for (long pc = 0; pc < (long)read_bytes; pc++) {' \
        '    switch(code[pc]) {' \
        '      case 62: if (ptr < 65535) ptr++; break;' \
        '      case 60: if (ptr > 0) ptr--; break;' \
        '      case 43: tape[ptr]++; break;' \
        '      case 45: tape[ptr]--; break;' \
        '      case 46: putchar(tape[ptr]); break;' \
        '      case 44: { int c = getchar(); tape[ptr] = (c == EOF) ? 0 : (unsigned char)c; break; }' \
        '      case 91: if (!tape[ptr]) { int b=1; while (b > 0 && ++pc < (long)read_bytes) { if (code[pc]==91) b++; else if (code[pc]==93) b--; } } break;' \
        '      case 93: if (tape[ptr]) { int b=1; while (b > 0 && --pc >= 0) { if (code[pc]==93) b++; else if (code[pc]==91) b--; } } break;' \
        '    }' \
        '  }' \
        '  free(code); return 0;' \
        '}' > /tmp/bf/bf.c && \
      gcc -O3 /tmp/bf/bf.c -o /usr/local/bin/beef && \
      rm -rf /tmp/bf; \
    fi

# Install Node.js (v20 LTS)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

# Install Go 1.23.6
RUN ARCH=$(dpkg --print-architecture) && \
    case "${ARCH}" in \
      amd64) GO_ARCH="amd64" ;; \
      arm64) GO_ARCH="arm64" ;; \
      *) echo "Unsupported architecture: ${ARCH}" && exit 1 ;; \
    esac && \
    curl -fsSL "https://go.dev/dl/go1.23.6.linux-${GO_ARCH}.tar.gz" -o /tmp/go.tar.gz && \
    tar -C /usr/local -xzf /tmp/go.tar.gz && \
    rm /tmp/go.tar.gz

ENV PATH="/usr/local/go/bin:/root/go/bin:${PATH}"

# Install templ CLI for Go
RUN go install github.com/a-h/templ/cmd/templ@latest

# Install Rust stable
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
ENV PATH="/root/.cargo/bin:${PATH}"

# Install Emscripten SDK
RUN git clone --depth 1 https://github.com/emscripten-core/emsdk.git /opt/emsdk && \
    cd /opt/emsdk && \
    ./emsdk install 3.1.64 && \
    ./emsdk activate 3.1.64

ENV EMSDK="/opt/emsdk"
ENV PATH="/opt/emsdk/upstream/emscripten:${PATH}"

# Initialize emscripten cache
RUN emcc --version

# Install PHP CLI, PHP XML (DOM), and Python Jinja2 for expanded templating stages
RUN apt-get update && apt-get install -y --no-install-recommends \
    php-cli \
    php-xml \
    python3-jinja2 \
    && rm -rf /var/lib/apt/lists/*

# Pre-install Node.js dependencies into system location to ensure
# modules resolve reliably even when /workspace is mounted without node_modules
WORKDIR /opt/node_app
COPY package.json package-lock.json /opt/node_app/
RUN npm ci && ln -s /opt/node_app/node_modules /node_modules

ENV NODE_PATH="/opt/node_app/node_modules:/workspace/node_modules"

# Embed complete repository sources into image
WORKDIR /workspace
COPY . /workspace

# Pre-fetch Go and Rust toolchain packages for offline self-containment
RUN cd stages/03_go_templ && go mod download
RUN cd stages/04_go_carchive && go mod download
RUN cd stages/06_rust_wasmtime && cargo fetch

CMD ["make", "all"]
