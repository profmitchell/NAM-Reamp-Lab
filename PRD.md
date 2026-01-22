
1. Swift + Audio Units (No JUCE needed!)

Swift has native Audio Unit support via AVFoundation. You can use the AVAudioUnit class and AVAudioUnitComponentManager to discover, load, and process audio through Audio Units without any third-party frameworks.

The key classes you’ll use are:

• AVAudioUnit for loading and managing AU instances

• AVAudioUnitComponentManager for discovering available plugins

• AudioComponentDescription for specifying which plugins to load

• AVAudioPCMBuffer for audio processing

This means you can:

• Load NAM Audio Unit plugin directly

• Chain multiple Audio Units together

• Real-time preview with low latency

• Save/load AU presets natively

• No JUCE framework needed at all

The workflow is: discover available Audio Units using the component manager, instantiate them asynchronously with AVAudioUnit.instantiate, then process audio buffers through them using the auAudioUnit.renderBlock method.


2. Embedding Python Training Pipeline in Swift

YES! You have several options to embed Python in your Swift app:

Option A: PythonKit (Recommended)

PythonKit is a Swift framework that lets you call Python code directly from Swift. You can import it via Swift Package Manager and then use it to:

• Import NAM’s Python modules directly

• Call nam.train.core.train() from Swift

• Pass parameters from Swift to Python seamlessly

• Get return values back as Swift-compatible types

The setup process involves:

1. Import PythonKit framework

2. Set the Python library path using PythonLibrary.useLibrary

3. Add NAM to Python’s sys.path

4. Import NAM modules using Python.import()

5. Call functions directly like nam.train()

You can wrap this in an ObservableObject class to make it reactive with SwiftUI, publishing training progress and status updates.

Option B: Process-based (Simpler, but less integrated)

Use Swift’s Process class to spawn Python as a subprocess. This approach:

• Calls python3 executable with command-line arguments

• Captures stdout/stderr using Pipe

• Streams output in real-time for progress monitoring

• Waits for completion with waitUntilExit()

Less integrated than PythonKit but easier to set up and debug.

Option C: Bundled Python Runtime (For Distribution)

Bundle a complete Python runtime inside your app bundle. This involves:

• Including Python.framework or standalone Python in your app

• Bundling NAM and all dependencies (torch, pytorch-lightning, etc.)

• Setting PYTHONPATH environment variable to your bundled packages

• Using either PythonKit or Process to execute

This makes your app completely self-contained and distributable without requiring users to install Python.


3. Complete Architecture

Here’s how the complete app would be structured:

App Entry Point:

• Main SwiftUI App struct

• Initialize Python on launch

• Create shared state objects (AudioUnitManager, PythonManager, ChainManager, Trainer)

Tab-based Interface:

Tab 1 - Chain Builder for Reamping:

• List of processing chains

• Each chain has multiple plugins (NAM models, Audio Units, IRs)

• Enable/disable individual chains

• Add/remove plugins from chains

• Process all enabled chains in batch

• Uses native Audio Unit hosting for processing

Tab 2 - Model Training:

• Input file picker (DI file)

• Output files picker (multiple reamped files)

• Batch train button

• Progress indicator

• Calls Python NAM training via PythonKit

• Monitors training progress in real-time

Tab 3 - Settings:

• Python runtime configuration

• Default training parameters

• Output folder preferences

• Audio Unit scan/refresh

Key Classes:

AppState (ObservableObject):

• Holds all managers as properties

• Shared across views via @EnvironmentObject

PythonManager:

• Initializes Python runtime

• Configures sys.path for NAM

• Verifies NAM installation

• Handles bundled vs system Python

AudioUnitHostManager:

• Discovers available Audio Units

• Loads AU instances

• Chains multiple AUs together

• Processes audio buffers

ChainManager:

• Manages list of processing chains

• Each chain has name, enabled state, and plugin list

• Save/load chain presets as JSON

NAMTrainer (ObservableObject):

• Wraps Python NAM training

• Published properties for progress and status

• async functions for single and batch training

• Real-time output streaming

ProcessingChain (struct):

• Identifiable with UUID

• Name, enabled flag

• Array of AudioPlugin objects

AudioPlugin (struct):

• Plugin type (NAM, VST3, AU, IR)

• File path or component identifier

• Preset data


4. Project Setup

Swift Package Dependencies:

Add PythonKit via Xcode’s Swift Package Manager:

• File menu → Add Packages

• URL: github.com/pvieito/PythonKit

• Version: 0.3.1 or later

Or in Package.swift manifest, add PythonKit to dependencies array.

Bundling NAM with your app:

Create a Run Script build phase in Xcode that:

1. Copies NAM Python package into your app’s Resources/python-packages folder

2. Installs Python dependencies using pip with -t flag to target your bundle

3. Creates proper directory structure: Contents/Resources/python-packages/nam

The script runs after compilation but before packaging, ensuring everything is included in the .app bundle.

Python Runtime Options:

For development: Use system Python at /usr/local/bin/python3 or user’s Python installation

For distribution: Bundle Python.framework from python.org in your app’s Frameworks folder, or use a standalone Python build


5. Advantages of This Approach

Use NAM’s training code as-is - No need to rewrite or convert to CoreML. The Python code works exactly as the maintainer intended, you get all bug fixes and updates automatically.

Native Audio Unit hosting - Swift’s AVFoundation provides first-class AU support. No JUCE means smaller binary, simpler build process, better macOS integration.

Beautiful Swift UI - SwiftUI gives you modern, responsive interface with minimal code. Native look and feel on macOS.

M4 Max GPU acceleration - Python’s PyTorch will automatically use Metal via MPS backend. Your M4 Max GPU will be fully utilized for training without any special configuration.

Distributable - Bundle everything users need. No “install Python first” instructions. Just download, drag to Applications, run.

Real-time preview - Audio Units run with extremely low latency. Preview your chains before batch processing.

Batch workflow - Complete pipeline in one app: build chains → batch reamp → batch train → export models.


6. Would This Work?

Absolutely! Here’s the complete workflow users would experience:

Step 1: Build Chains

• Add new chain

• Give it a descriptive name like “Clean_Boost_AmpA”

• Add NAM models from your library

• Add impulse responses

• Preview in real-time through Audio Units

• Save chain preset

Step 2: Batch Reamp

• Load NAM input.wav file

• Select which chains to process (checkboxes)

• Click “Process All Chains”

• App processes input through each enabled chain using native AU hosting

• Outputs saved as: Clean_Boost_AmpA.wav, OD_Heavy_AmpB.wav, etc.

Step 3: Batch Train

• Switch to Training tab

• Input file is still loaded

• App automatically detects your processed output files

• Select which ones to train

• Click “Train All Models”

• Python NAM training runs via PythonKit

• Progress bar shows overall completion

• GPU automatically used via MPS

Step 4: Use Models

• Trained .nam files automatically saved

• Load directly into NAM plugin

• Each named after its processing chain


7. Implementation Priorities

Phase 1 - MVP:

• Basic SwiftUI interface with file pickers

• PythonKit integration calling NAM training

• Simple list of output files to train

• Progress monitoring

Phase 2 - Audio Processing:

• Audio Unit discovery and loading

• Single chain processing

• Save/load chain presets as JSON

Phase 3 - Batch Features:

• Multiple chain management

• Batch reamp processing

• Batch training queue

• Error handling and recovery

Phase 4 - Polish:

• Real-time audio preview

• Drag-and-drop file handling

• Chain templates library

• Training parameter presets

• Automatic model organization


8. Alternative Approaches Considered

CoreML conversion: Would require converting NAM models to CoreML format. Not needed since Python works fine and you want to use training as-is.

Pure Python GUI with Tkinter: Would work but wouldn’t be as nice as native Swift UI, and wouldn’t integrate Audio Units as cleanly.

Electron app: Cross-platform but huge bundle size and not native-feeling on macOS.

JUCE-based app: Could host AUs but requires C++, more complex build process, and you’d still need Python integration for training.

The Swift + PythonKit + AVFoundation approach gives you the best of all worlds: native performance, beautiful UI, Python integration, and Audio Unit hosting.


9. Getting Started

If you want to build this, here’s the recommended path:

Week 1: Create basic Xcode project with SwiftUI, add PythonKit, verify you can import NAM Python modules and call simple functions.

Week 2: Build basic training interface - file pickers, call nam.train.core.train() for single model, display progress.

Week 3: Add batch training - multiple output files, loop through them, progress tracking.

Week 4: Start Audio Unit hosting - discover AUs, load NAM plugin, process audio buffer through it.

Week 5: Build chain management - multiple plugins per chain, save/load presets.

Week 6: Integrate everything - complete workflow from chain building through training.


This would genuinely be an amazing tool for the NAM community! The combination of Swift’s native capabilities with Python’s existing training code is perfect. You get the best UI/UX while leveraging all the hard work already done in the NAM Python codebase.