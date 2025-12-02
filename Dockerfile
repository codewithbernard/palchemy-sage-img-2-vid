# Build argument for base image selection
# Use a CUDA 12.8 "devel" image so nvcc is available for compiling SageAttention
ARG BASE_IMAGE=nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04

# =========================
# Stage 1: Base image
# =========================
FROM ${BASE_IMAGE} AS base

# --- General build args (you can drop these if you don't need them anymore)
ARG ENABLE_PYTORCH_UPGRADE=false
ARG PYTORCH_INDEX_URL=https://download.pytorch.org/whl/cu128

# Non-interactive apt, faster pip, etc.
ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_PREFER_BINARY=1
ENV PYTHONUNBUFFERED=1
ENV CMAKE_BUILD_PARALLEL_LEVEL=8

# Build for a wide range of modern NVIDIA architectures
# (Turing, Ampere, Ada, Hopper, Blackwell)
ENV TORCH_CUDA_ARCH_LIST="7.5;8.0;8.6;8.9;9.0;10.0;12.0"

# System deps (no system Python; we’ll use uv to install Python 3.11)
RUN apt-get update && apt-get install -y \
    git \
    wget \
    curl \
    ca-certificates \
    build-essential \
    pkg-config \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# Install uv and set up a Python 3.11 virtual environment
# uv will download and manage CPython 3.11 for us
RUN wget -qO- https://astral.sh/uv/install.sh | sh \
    && ln -s /root/.local/bin/uv /usr/local/bin/uv \
    && ln -s /root/.local/bin/uvx /usr/local/bin/uvx \
    && uv python install 3.11 \
    && uv venv --python 3.11 /opt/venv

# Use the virtual environment for everything from here on
ENV PATH="/opt/venv/bin:${PATH}"

# Upgrade core Python packaging tools inside the venv
RUN uv pip install --upgrade pip setuptools wheel

# =========================
# ComfyUI + ComfyUI-Manager
# =========================

# Clone ComfyUI core
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /comfyui

# Clone ComfyUI-Manager into custom_nodes
RUN git clone https://github.com/comfy-org/ComfyUI-Manager.git \
    /comfyui/custom_nodes/ComfyUI-Manager

# First install PyTorch 2.9 + CUDA 12.8 wheels, TorchVision, TorchAudio
# from the official PyTorch cu128 wheel index
RUN uv pip install \
      --index-url ${PYTORCH_INDEX_URL} \
      torch==2.9.0 \
      torchvision==0.20.0 \
      torchaudio==2.9.0

# Install Triton 3.5 (required by SageAttention)
RUN uv pip install triton==3.5.0

# Now install ComfyUI dependencies (they should accept torch 2.9)
RUN cd /comfyui && \
    uv pip install --no-cache-dir -r requirements.txt && \
    uv pip install --no-cache-dir -r manager_requirements.txt

# =========================
# SageAttention build (PEP 517 wheel)
# =========================

# Clone SageAttention
RUN git clone https://github.com/thu-ml/SageAttention.git /opt/SageAttention

# Build a wheel via PEP 517 (python -m build) using our existing env
# and the globally set TORCH_CUDA_ARCH_LIST
RUN cd /opt/SageAttention && \
    uv pip install build && \
    EXT_PARALLEL=4 NVCC_APPEND_FLAGS="--threads 8" MAX_JOBS=32 \
    python -m build --wheel --no-isolation && \
    uv pip install --no-deps dist/sageattention-*.whl

# =========================
# Back to your original layout
# =========================

# Change working directory to ComfyUI
WORKDIR /comfyui

# Support for the network volume (your existing config)
ADD src/extra_model_paths.yaml ./

# Go back to root
WORKDIR /

# Python runtime deps for your handler
RUN uv pip install runpod requests websocket-client

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

WORKDIR /comfyui

FROM base AS final

# install custom nodes
RUN comfy-node-install comfyui-custom-scripts
RUN comfy-node-install comfyui-easy-use
RUN comfy-node-install comfyui-frame-interpolation
RUN comfy-node-install ComfyUI-WanVideoWrapper
RUN comfy-node-install comfyui-kjnodes