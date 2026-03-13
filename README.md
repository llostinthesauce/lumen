# Lumen

A privacy-focused SwiftUI interface for running Large Language Models locally on Mac and iOS. Built on Apple's MLX framework, exploring native GUI patterns for model management, RAG workspaces, and performance telemetry.

## Features

### Local Intelligence
Run state-of-the-art open-source models (Llama 3, Mistral, Gemma) directly on your device. Optimized for Apple Silicon via the MLX framework.

### RAG (Retrieval-Augmented Generation)
Chat with your own data.
- **Drag & Drop Intake**: Add files and folders to your workspace.
- **Local Indexing**: Documents processed, chunked, and indexed entirely on-device.
- **Workspaces**: Organize context with custom workspaces and ignore patterns.

### Model Management
- **In-App Catalog**: Discover models with details on size, quantization, and memory requirements.
- **One-Click Downloads**: Download and install models from Hugging Face.
- **Smart Management**: Auto-checks for compatibility, simple load/unload controls.

### Telemetry & Performance
- **Live HUD**: Monitor token-per-second (TPS) speeds and active model status.
- **Resource Tracking**: RAM, VRAM, and Unified Memory usage.
- **Thermal State**: Device thermals during intensive tasks.

## Tech Stack
- **Swift / SwiftUI**: Native macOS and iOS UI.
- **[MLX Swift](https://github.com/ml-explore/mlx-swift)**: Apple's ML array framework for on-device inference.

## Requirements
- **macOS**: 14.0 (Sonoma) or later
- **iOS**: 17.0 or later
- **Hardware**: Apple Silicon (M1/M2/M3/M4)
