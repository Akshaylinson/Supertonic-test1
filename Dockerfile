FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# ── Base build tools + prerequisites for external repos ──────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake pkg-config git git-lfs curl ca-certificates \
    gnupg apt-transport-https software-properties-common \
    python3 python3-pip pipx \
    nodejs npm \
    golang-go \
    openjdk-17-jdk maven \
    nlohmann-json3-dev libomp-dev bc \
    && rm -rf /var/lib/apt/lists/*

# ── .NET 9 (official install script) ────────────────────────────────────────
RUN curl -fsSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel 9.0 --install-dir /usr/local/dotnet
ENV PATH="/usr/local/dotnet:${PATH}"
ENV DOTNET_ROOT=/usr/local/dotnet

# ── ONNX Runtime 1.21 (C++ headers + shared lib, downloaded directly) ─────────
ENV ORT_VERSION=1.21.0
RUN curl -fsSL \
    https://github.com/microsoft/onnxruntime/releases/download/v${ORT_VERSION}/onnxruntime-linux-x64-${ORT_VERSION}.tgz \
    | tar -xz -C /usr/local --strip-components=1 && \
    ldconfig

# ── Rust ─────────────────────────────────────────────────────────────────────
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain stable
ENV PATH="/root/.cargo/bin:${PATH}"

# ── uv (Python package manager) ──────────────────────────────────────────────
RUN pipx install uv
ENV PATH="/root/.local/bin:${PATH}"

# ── ONNX Runtime paths ────────────────────────────────────────────────────────
ENV ONNXRUNTIME_LIB_PATH=/usr/local/lib/libonnxruntime.so

WORKDIR /app

# ── Download ONNX model assets from Hugging Face via git-lfs ─────────────────
RUN git lfs install && \
    git clone --depth=1 https://huggingface.co/Supertone/supertonic-3 assets

# ── Copy source ───────────────────────────────────────────────────────────────
COPY . .

# ── Pre-install language dependencies (layer-cache friendly) ─────────────────

# Python
RUN cd /app/py && uv sync

# Node.js
RUN cd /app/nodejs && npm install --silent

# Go
RUN cd /app/go && go mod download

# Rust
RUN cd /app/rust && cargo fetch

# Java
RUN cd /app/java && mvn -Dmaven.repo.local=/app/.m2/repository dependency:go-offline -q

# C#
RUN cd /app/csharp && dotnet restore

# C++
RUN cmake -S /app/cpp -B /app/cpp/build \
        -DCMAKE_BUILD_TYPE=Release \
        -DONNXRUNTIME_INCLUDE_DIR=/usr/local/include \
        -DONNXRUNTIME_LIB=/usr/local/lib/libonnxruntime.so && \
    cmake --build /app/cpp/build --config Release

# ── Entry point ───────────────────────────────────────────────────────────────
# TEST_MODE env var drives test_all.sh non-interactively (1=default, 4=all)
ENV TEST_MODE=1
ENV CLEAN_RESULTS=n

CMD ["/bin/bash", "test_all.sh"]
