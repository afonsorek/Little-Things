#!/bin/bash
# Little Things — REAPER Plugin Installer
# Installs the Launchpad Chop Engine into REAPER

set -e

echo "╔══════════════════════════════════════════════╗"
echo "║  Little Things — Launchpad Chop Engine       ║"
echo "║  REAPER Plugin Installer                     ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# Detect REAPER resource path
REAPER_PATH="$HOME/Library/Application Support/REAPER"

if [ ! -d "$REAPER_PATH" ]; then
    echo "❌ REAPER resource directory not found at:"
    echo "   $REAPER_PATH"
    echo ""
    echo "Please make sure REAPER is installed."
    echo "Or set REAPER_PATH manually and re-run."
    exit 1
fi

echo "✓ Found REAPER at: $REAPER_PATH"
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Install Lua script
echo "📦 Installing Lua script..."
cp "$SCRIPT_DIR/Little Things - Launchpad Chop Engine.lua" "$REAPER_PATH/Scripts/"
echo "   → Scripts/Little Things - Launchpad Chop Engine.lua"

# Install JSFX
echo "📦 Installing JSFX MIDI Bridge..."
cp "$SCRIPT_DIR/Little Things/LittleThings_MIDI_Bridge.jsfx" "$REAPER_PATH/Effects/"
echo "   → Effects/LittleThings_MIDI_Bridge.jsfx"

# Install presets
echo "📦 Installing kit presets..."
mkdir -p "$REAPER_PATH/Scripts/LittleThings_Kits"
if [ -d "$SCRIPT_DIR/Little Things/Presets" ]; then
    cp "$SCRIPT_DIR/Little Things/Presets/"*.ltkit "$REAPER_PATH/Scripts/LittleThings_Kits/" 2>/dev/null || true
    echo "   → Scripts/LittleThings_Kits/*.ltkit"
fi

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  ✅ Installation complete!                   ║"
echo "╠══════════════════════════════════════════════╣"
echo "║                                              ║"
echo "║  Next steps:                                 ║"
echo "║  1. Open REAPER                              ║"
echo "║  2. Install ReaImGui via ReaPack             ║"
echo "║     (Extensions → ReaPack → Browse)          ║"
echo "║  3. Actions → Show Action List               ║"
echo "║  4. Load ReaScript... → select the script    ║"
echo "║  5. Run the action!                          ║"
echo "║                                              ║"
echo "╚══════════════════════════════════════════════╝"
