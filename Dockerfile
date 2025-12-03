# Build argument for base image selection
# Use a CUDA 12.8 "devel" image so nvcc is available for compiling SageAttention
ARG BASE_IMAGE=nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04

# =========================
# Stage 1: Base image
# =========================
FROM ${BASE_IMAGE} AS base

# --- General build args (you can drop these if you don't need them anymore)
ARG PYTHON_VERSION=3.11
ARG TRITON_VERSION=3.5.0
ARG SAGE_BRANCH=main   # or a tag/commit you like

ENV DEBIAN_FRONTEND=noninteractive \
    CUDA_HOME=/usr/local/cuda \
    # Target only the GPUs you listed:
    # A40 (8.6), Ada & 4090 & L4 (8.9), H200 (9.0), B200 (10.0), 5090 (12.0)
    TORCH_CUDA_ARCH_LIST="8.6;8.9;9.0;10.0;12.0" \
    MAX_JOBS=32

# -----------------------------
# Base system + Python
# -----------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    python${PYTHON_VERSION} python3-pip python3-venv python3-dev \
    git build-essential ninja-build ca-certificates \
    && ln -sf /usr/bin/python${PYTHON_VERSION} /usr/bin/python3 \
    && python3 -m pip install --upgrade pip \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"

# -----------------------------
# 1) PyTorch 2.9 + CUDA 12.8, Triton, SageAttention runtime deps
# -----------------------------
# On Linux, `pip install torch` gives 2.9.0 with bundled CUDA 12.8. :contentReference[oaicite:5]{index=5}
RUN python -m pip install --upgrade pip setuptools wheel \
    && python -m pip install \
    torch torchvision torchaudio \
    && python -m pip install \
    triton==${TRITON_VERSION} \
    build>=1.2

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

# -----------------------------
# 2) Build SageAttention wheel with PEP 517 for these archs
# -----------------------------
WORKDIR /opt
RUN git clone https://github.com/thu-ml/SageAttention.git
WORKDIR /opt/SageAttention

# PEP 517 build, reuse current env (torch+triton) instead of build isolation
RUN python -m build --wheel --no-isolation

# Install the wheel into the image (optional, but usually what you want)
RUN python -m pip install dist/sageattention-*.whl

# Default workdir for your app
WORKDIR /workspace

# =========================
# ComfyUI + ComfyUI-Manager
# =========================

# Clone ComfyUI core
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /comfyui

# Clone ComfyUI-Manager into custom_nodes
RUN git clone https://github.com/comfy-org/ComfyUI-Manager.git \
    /comfyui/custom_nodes/ComfyUI-Manager

# Now install ComfyUI dependencies (they should accept torch 2.9)
RUN cd /comfyui && \
    uv pip install --no-cache-dir -r requirements.txt && \
    uv pip install --no-cache-dir -r manager_requirements.txt


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

ARG HUGGINGFACE_ACCESS_TOKEN

# Install comfy-cli for model/node management
# RUN uv pip install comfy-cli

# Disable comfy-cli telemetry and skip all prompts
# RUN comfy --skip-prompt tracking disable
# RUN comfy --workspace /comfyui

# install custom nodes
# RUN comfy-node-install comfyui-custom-scripts
# RUN comfy-node-install comfyui-easy-use
# RUN comfy-node-install comfyui-frame-interpolation
# RUN comfy-node-install ComfyUI-WanVideoWrapper
# RUN comfy-node-install comfyui-kjnodes

# vae
# RUN comfy model download --url https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors --relative-path models/vae --filename wan_2.1_vae.safetensors

# diffusion models
# RUN comfy model download --url https://huggingface.co/FX-FeiHou/wan2.2-Remix/resolve/main/NSFW/Wan2.2_Remix_NSFW_i2v_14b_high_lighting_v2.0.safetensors --relative-path models/diffusion_models --filename Wan2.2_Remix_NSFW_i2v_14b_high_lighting_v2.0.safetensors
# RUN comfy model download --url https://huggingface.co/FX-FeiHou/wan2.2-Remix/resolve/main/NSFW/Wan2.2_Remix_NSFW_i2v_14b_low_lighting_v2.0.safetensors --relative-path models/diffusion_models --filename Wan2.2_Remix_NSFW_i2v_14b_low_lighting_v2.0.safetensors

# text encoders
# RUN comfy model download --url https://huggingface.co/NSFW-API/NSFW-Wan-UMT5-XXL/resolve/main/nsfw_wan_umt5-xxl_fp8_scaled.safetensors --relative-path models/text_encoders --filename nsfw_wan_umt5-xxl_fp8_scaled.safetensors

# loras
# RUN comfy model download --url https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/LoRAs/Wan22-Lightning/old/Wan2.2-Lightning_I2V-A14B-4steps-lora_HIGH_fp16.safetensors --relative-path models/loras --filename Wan2.2-Lightning_I2V-A14B-4steps-lora_HIGH_fp16.safetensors
# RUN comfy model download --url https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/LoRAs/Wan22-Lightning/old/Wan2.2-Lightning_I2V-A14B-4steps-lora_LOW_fp16.safetensors --relative-path models/loras --filename Wan2.2-Lightning_I2V-A14B-4steps-lora_LOW_fp16.safetensors