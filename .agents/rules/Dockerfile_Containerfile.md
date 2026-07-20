---
paths:
  - "**/Dockerfile"
  - "**/Dockerfile.*"
  - "**/Containerfile"
---

# Dockerfile / Containerfile Style Guide

- Prefer `Dockerfile` over `Containerfile`.  Use Podman's `--format docker`
  flag (or equivalent) for compatibility.
- Use BuildKit syntax headers: `# syntax=docker/dockerfile:1`
- Use `RUN --mount=type=cache` for package manager and build caches.
- Set `SHELL ["/bin/bash", "-o", "pipefail", "-c"]` (or equivalent safe shell)
  early in the Dockerfile.
- Minimize layers: combine related `RUN` instructions.
- Use `--no-install-recommends` (apt) or equivalent for minimal installs.
- Prefer multi-stage builds to keep final images small.
