# NAM Reamp Lab

A macOS application for creating Neural Amp Modeler (NAM) training data by processing audio through chains of Audio Unit plugins. Build your perfect amp tone using real plugins, then train a NAM model to capture it.

![macOS](https://img.shields.io/badge/macOS-13.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Overview

NAM Reamp Lab streamlines the workflow of creating NAM models from your existing amp sim plugins:

1. **Build Processing Chains** - Stack Audio Unit plugins (amp sims, pedals, cab IRs) in any order
2. **Process Audio** - Run your clean DI recordings through the chains to generate "reamped" output
3. **Train NAM Models** - Use the processed audio pairs to train Neural Amp Modeler models
4. **Export .nam Files** - Get portable neural amp models you can use anywhere

## Features

### 🎸 Chain Builder
- Load any Audio Unit (AU) effect plugins installed on your system
- Stack multiple plugins in a processing chain
- Real-time preview with live monitoring
- Full plugin UI support - tweak knobs and settings just like in your DAW
- Save and load chain presets
- Impulse Response (IR) loading for cabinet simulation

### 🧠 NAM Training Integration
- Automatic training job creation from processed chains
- Integrated Python environment management
- Support for NAM's training architectures (WaveNet, LSTM, etc.)
- GPU acceleration via Apple Metal Performance Shaders (MPS)
- Training progress monitoring and logs

### 🎛️ Audio I/O
- Select input/output audio devices
- Real-time level metering
- Configurable buffer size and sample rate
- Direct monitoring capability

## Requirements

- **macOS 15.0** (Sequoia) or later
- **Xcode 15.0** or later (for building)
- **Python 3.10** with PyTorch (for training - NOT 3.14, MPS issues)
- Audio Unit plugins you want to capture

## Installation

### From Source

```bash
# Clone the repository
git clone https://github.com/yourusername/NAM-Reamp-Lab.git
cd NAM-Reamp-Lab

# Open in Xcode
open "NAM Reamp Lab.xcodeproj"

# Build and run (⌘R)
```

### Python Environment Setup

For training functionality, set up a Python 3.10 environment (3.10 specifically - newer versions have MPS issues):

```bash
# Create virtual environment with Python 3.10
python3.10 -m venv .venv
source .venv/bin/activate

# Install PyTorch with MPS support
pip install torch torchvision torchaudio

# Install NAM training package
pip install neural-amp-modeler

# Verify MPS is available
python -c "import torch; print('MPS:', torch.backends.mps.is_available())"
```

## Usage

### Quick Start

1. **Select Input File** - Choose a clean DI recording (the signal before any amp/effects)
2. **Create a Chain** - Click "New Chain" and add your amp sim plugins
3. **Configure Plugins** - Click on plugins to open their UI and dial in your tone
4. **Process & Train** - Click "Process & Train" to generate output files and create training jobs
5. **Train Models** - Switch to the Training tab and start training

### Workflow Tips

- Use a standardized input signal (NAM provides test signals, or use your own DI recordings)
- Create multiple chains to capture different tones from the same amp sim
- For best results, use 3-5 minutes of varied playing styles
- Training typically takes 10-30 minutes depending on settings

### Chain Presets

Export your chains as `.namchain` files to share with others or backup your configurations.

## Project Structure

```
NAM Reamp Lab/
├── NAM Reamp Lab/          # Main app source
│   ├── Audio/              # Audio engine and modular logic
│   ├── Managers/           # Business logic managers
│   ├── Models/             # Data models
│   └── Views/              # SwiftUI views and components
├── neural-amp-modeler-main/ # NAM Python package (training)
└── ...
```

### Modular Backend
The core `AudioEngine` is modularized into specialized extensions for better readability:
- **`AudioEngine+Plugins.swift`**: Handles complex AU and NAM plugin loading.
- **`AudioEngine+Metering.swift`**: High-performance RMS metering using vDSP.
- **`AudioEngine+Devices.swift`**: Hardware discovery and CoreAudio device configuration.

## Technical Details

### Audio Processing
- Uses `AVAudioEngine` for real-time audio routing
- **In-process Audio Unit loading** for reliable offline rendering
- Chunk-based processing (4096 samples) - handles any file length
- Real-time convolution for IR processing via Accelerate/vDSP
- Plugin preset/state saving and restoration during batch processing

### Plugin Hosting
- Full Audio Unit v3 support
- Custom plugin UI hosting via `AUViewController`
- In-process loading for offline rendering (out-of-process causes error 4099)

### Training
- Subprocess-based Python execution with clean environment spawning
- Uses `nam-full` CLI with WaveNet architecture
- Automatic MPS (Metal) GPU detection on Apple Silicon
- ESR (Error Signal Ratio) display with color-coded quality indicators
- Models saved directly to configured folder with chain name

## Known Limitations

- Audio Units only (no VST/VST3 support - macOS limitation)
- Some plugins may not expose all parameters via AU interface
- Training requires separate Python environment setup

## Contributing

Contributions are welcome! Please feel free to submit pull requests.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Neural Amp Modeler](https://github.com/sdatkinson/neural-amp-modeler) by Steven Atkinson
- [NAM Plugin](https://github.com/sdatkinson/NeuralAmpModelerPlugin) for the AU/VST plugin
- The NAM community for testing and feedback

## Support

- 🐛 [Report bugs](https://github.com/yourusername/NAM-Reamp-Lab/issues)
- 💡 [Request features](https://github.com/yourusername/NAM-Reamp-Lab/issues)
- 💬 [Discussions](https://github.com/yourusername/NAM-Reamp-Lab/discussions)

---

Made with ❤️ for guitar tone nerds
