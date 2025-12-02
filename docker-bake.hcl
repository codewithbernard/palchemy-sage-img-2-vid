variable "DOCKERHUB_REPO" {
  default = "runpod"
}

variable "DOCKERHUB_IMG" {
  default = "worker-comfyui"
}

variable "RELEASE_VERSION" {
  default = "sage-cu128"
}

# Single source of truth: use the devel image, not runtime
variable "BASE_IMAGE" {
  default = "nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04"
}

group "default" {
  targets = ["base", "final"]
}

target "base" {
  context   = "."
  dockerfile = "Dockerfile"
  target    = "base"
  platforms = ["linux/amd64"]
  args = {
    BASE_IMAGE = "${BASE_IMAGE}"
    # These are now NOOP in your Dockerfile but kept for compatibility
    ENABLE_PYTORCH_UPGRADE = "false"
    PYTORCH_INDEX_URL      = "https://download.pytorch.org/whl/cu128"
  }
  tags = ["${DOCKERHUB_REPO}/${DOCKERHUB_IMG}:${RELEASE_VERSION}-base"]
}

target "final" {
  context   = "."
  dockerfile = "Dockerfile"
  target    = "final"
  platforms = ["linux/amd64"]
  args = {
    BASE_IMAGE = "${BASE_IMAGE}"
    ENABLE_PYTORCH_UPGRADE = "false"
    PYTORCH_INDEX_URL      = "https://download.pytorch.org/whl/cu128"
  }
  tags = ["${DOCKERHUB_REPO}/${DOCKERHUB_IMG}:${RELEASE_VERSION}"]
  inherits = ["base"]
}