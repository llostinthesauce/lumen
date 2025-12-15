# Lumen

> [!NOTE]
> **Work in Progress**: This project is currently under active development. Features, APIs, and interfaces are subject to change.

Lumen is a powerful, privacy-focused interface for running Large Language Models (LLMs) locally on your Mac and iOS devices. Built on Apple's **MLX** framework, Lumen leverages the full potential of Apple Silicon to deliver high-performance, low-latency AI interactions without ever sending data to the cloud.

## Features

### 🧠 Local Intelligence
Run state-of-the-art open-source models (like Llama 3, Mistral, Gemma) directly on your device. Lumen is optimized for Apple Silicon, ensuring efficient memory usage and fast inference speeds via the MLX framework.

### 📚 RAG (Retrieval-Augmented Generation)
Chat with your own data. Lumen features a robust RAG system that allows you to:
- **Drag & Drop Intake**: Easily add files and folders to your workspace.
- **Local Indexing**: Documents are processed, chunked, and indexed entirely on your device.
- **Context-Aware**: Get answers based on the specific content of your documents.
- **Workspaces**: Organize your context with custom workspaces and ignore patterns.

### ⚙️ Model Management
- **In-App Catalog**: Discover models with details on size, quantization, and memory requirements.
- **One-Click Downloads**: Seamlessly download and install models from Hugging Face.
- **Smart Management**: Manage your local model library with auto-checks for compatibility and simple load/unload controls.

### 📊 Telemetry & Performance
Real-time insights into your system's performance:
- **Live HUD**: Monitor token-per-second (TPS) speeds and active model status.
- **Resource Tracking**: Visual indicators for RAM, VRAM, and Unified Memory usage.
- **Thermal State**: Keep an eye on device thermals during intensive tasks.

## Tech Stack
- **Swift / SwiftUI**: Native, responsive user interface for macOS and iOS.
- **[MLX Swift](https://github.com/ml-explore/mlx-swift)**: Apple's machine learning array framework for efficient on-device inference.

## Requirements
- **macOS**: macOS 14.0 (Sonoma) or later.
- **iOS**: iOS 17.0 or later.
- **Hardware**: Mac with Apple Silicon (M1/M2/M3/M4) required for MLX acceleration.

## Development
This is a personal project exploring the capabilities of local LLMs on Apple hardware.
