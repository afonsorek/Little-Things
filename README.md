# Little Things — Launchpad Chop Engine

**Little Things** transforma qualquer trecho de áudio em um kit pronto para tocar no **Novation Launchpad**. Ele captura o áudio da sua track, fatia automaticamente e distribui as fatias nos pads — com as cores acesas no próprio Launchpad.

Disponível como **script nativo para o REAPER**.

---

## ✨ Recursos

- ✂️ **Fatiamento inteligente** — Divisão igualitária.
- 🟩 **8, 16, 32 ou 64 pads** — as fatias vão direto para o Launchpad.
- 🌈 **Feedback visual** — cada pad acende com a cor da sua fatia.
- 💾 **Presets de kits** (`.ltkit`) — salve e recarregue seus kits.

---

## 📦 Conteúdo

```
Plugins/
├── VST3/Little Things.vst3          # VST3 com ARA 2
├── AU/Little Things.component       # Audio Unit (Logic Pro e outros)
└── Standalone/Little Things.app     # Aplicativo independente
REAPER Script/
├── Little Things - Launchpad Chop Engine.lua   # Script ReaImGui
├── Little Things/
│   ├── LittleThings_MIDI_Bridge.jsfx           # Bridge MIDI
│   └── Presets/                                # Kits de exemplo
└── install_reaper.sh                           # Instalador para o REAPER
```

---

## 🛠️ Instalação

### Script do REAPER
Requer a extensão **[ReaImGui](https://github.com/cfillion/reaimgui)** (disponível via ReaPack).

**Via ReaPack (recomendado):**
1. No REAPER: **Extensions → ReaPack → Import repositories...**
2. Cole a URL:
   ```
   https://github.com/afonsorek/Little-Things/raw/main/index.xml
   ```
3. Em **Extensions → ReaPack → Browse packages**, procure por **Little Things** e instale.

Ou carregue o `.lua` manualmente em **Actions → Show action list → New action → Load ReaScript**.

---

## 🚀 Como usar

1. Conecte o **Launchpad MK3** via USB, e ative as opções de input e output dentro do reaper.
2. Acione o script **Little Things**.
3. Nas configurações do script, selecione o Midi IN e Midi out da sua launchpad.
4. Pronto — o Launchpad acende e já está pronto para tocar! 🎶

---

## 📋 Requisitos

- Novation Launchpad
- REAPER 7+ com ReaImGui

---

## 📄 Licença

Veja o arquivo [LICENSE](LICENSE).
