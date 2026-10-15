#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=================================================="
echo "    Instalador dos Plugins Little Things (macOS)  "
echo "=================================================="
echo ""

mkdir -p "$HOME/Library/Audio/Plug-Ins/VST3"
mkdir -p "$HOME/Library/Audio/Plug-Ins/Components"

echo "-> Instalando VST3..."
cp -R "$DIR/Plugins/VST3/Little Things.vst3" "$HOME/Library/Audio/Plug-Ins/VST3/"

echo "-> Instalando AU (Audio Unit)..."
cp -R "$DIR/Plugins/AU/Little Things.component" "$HOME/Library/Audio/Plug-Ins/Components/"

echo ""
echo "=================================================="
echo "  [OK] Instalacao concluida com sucesso!         "
echo "=================================================="
echo ""
echo "Pastas instaladas:"
echo " - VST3: ~/Library/Audio/Plug-Ins/VST3/Little Things.vst3"
echo " - AU:   ~/Library/Audio/Plug-Ins/Components/Little Things.component"
echo ""
echo "Abra ou reinicie sua DAW (REAPER, Logic Pro, Studio One, Ableton, etc)."
echo ""
read -p "Pressione Enter para sair..."
