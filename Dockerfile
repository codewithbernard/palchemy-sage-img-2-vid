ARG BASE_IMAGE=nvidia/cuda:12.6.3-cudnn-runtime-ubuntu24.04
FROM ${BASE_IMAGE}

# Optional: pin a specific ComfyUI version/commit/tag
ARG COMFYUI_VERSION=latest

# -----------------------------------------------------------------------------
# Environment
# -----------------------------------------------------------------------------
ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_PREFER_BINARY=1
ENV PYTHONUNBUFFERED=1
ENV CMAKE_BUILD_PARALLEL_LEVEL=8
ENV IMAGEIO_FFMPEG_EXE=/usr/bin/ffmpeg

# (Usually set by base image, but safe to reinforce)
ENV PATH=/usr/local/cuda/bin:${PATH}
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH}

# -----------------------------------------------------------------------------
# System packages – dev-friendly, like your working image
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y \
    python3.12 \
    python3.12-venv \
    python3.12-dev \
    python3-pip \
    build-essential \
    git \
    wget \
    curl \
    ca-certificates \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    ffmpeg \
    && ln -sf /usr/bin/python3.12 /usr/bin/python3 \
    && ln -sf /usr/bin/python3.12 /usr/bin/python \
    && ln -sf /usr/bin/pip3 /usr/bin/pip \
    && apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# Upgrade pip toolchain
RUN python3 -m pip install --upgrade pip setuptools wheel

# Just in case the base image had uv – nuke it so everything uses pip
RUN pip uninstall -y uv 2>/dev/null || true && \
    rm -f /usr/local/bin/uv /usr/local/bin/uvx 2>/dev/null || true

# -----------------------------------------------------------------------------
# PyTorch (CUDA 12.4 wheels – compatible with this runtime)
# -----------------------------------------------------------------------------
RUN pip install --no-cache-dir \
    torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124

# -----------------------------------------------------------------------------
# ComfyUI – cloned and installed pip-style (like your old Dockerfile)
# -----------------------------------------------------------------------------

# Clone ComfyUI core
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /comfyui

# Clone ComfyUI-Manager into custom_nodes
RUN git clone https://github.com/comfy-org/ComfyUI-Manager.git \
    /comfyui/custom_nodes/ComfyUI-Manager

WORKDIR /comfyui

# Now install ComfyUI dependencies (they should accept torch 2.9)
RUN pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir -r manager_requirements.txt && \
    pip install --no-cache-dir GitPython opencv-python

# -----------------------------------------------------------------------------
# Python runtime deps for your handler
# -----------------------------------------------------------------------------

# Go back to root
WORKDIR /

# Python runtime deps for your handler
RUN pip install runpod requests websocket-client

# Add application code and scripts (unchanged from your original)
ADD src/start.sh handler.py test_input.json ./
RUN chmod +x /start.sh

# Add script to install custom nodes
COPY scripts/comfy-node-install.sh /usr/local/bin/comfy-node-install
RUN chmod +x /usr/local/bin/comfy-node-install

# Prevent pip from asking for confirmation during uninstall steps in custom nodes
ENV PIP_NO_INPUT=1

# Copy helper script to switch Manager network mode at container start
COPY scripts/comfy-manager-set-mode.sh /usr/local/bin/comfy-manager-set-mode
RUN chmod +x /usr/local/bin/comfy-manager-set-mode

# Default command
CMD ["/start.sh"]

# -----------------------------------------------------------------------------
# Final stage – Comfy nodes and models
# -----------------------------------------------------------------------------