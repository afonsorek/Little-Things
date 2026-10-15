# Little Things — Launchpad Chop Engine

**Little Things** transforma qualquer trecho de áudio em um kit pronto para tocar no **Novation Launchpad**. Ele captura o áudio da sua track, fatia automaticamente e distribui as fatias nos pads — com as cores acesas no próprio Launchpad.

Disponível como **plugin (VST3 / AU / Standalone) com ARA 2** e como **script nativo para o REAPER**.

---

## ✨ Recursos

- 🎛️ **Captura instantânea via ARA 2** — carrega a timeline da track sem precisar renderizar (REAPER, Studio One, Logic Pro, Cubase).
- ⏺️ **Modo Play-to-Render** — para hosts sem ARA: arme, dê play e finalize.
- ✂️ **Fatiamento inteligente** — por transientes, grade de compassos ou divisão igualitária.
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
├── LittleThings_MIDI_Bridge.jsfx               # Bridge MIDI
├── Presets/                                    # Kits de exemplo
└── install_reaper.sh                           # Instalador para o REAPER
```

---

## 🛠️ Instalação (macOS)

### Plugins
Copie os arquivos para as pastas de plugins do usuário:

| Formato | Destino |
|---|---|
| `Little Things.vst3` | `~/Library/Audio/Plug-Ins/VST3/` |
| `Little Things.component` | `~/Library/Audio/Plug-Ins/Components/` |

Ou pelo Terminal, a partir desta pasta:

```bash
mkdir -p ~/Library/Audio/Plug-Ins/{VST3,Components}
cp -R "Plugins/VST3/Little Things.vst3" ~/Library/Audio/Plug-Ins/VST3/
cp -R "Plugins/AU/Little Things.component" ~/Library/Audio/Plug-Ins/Components/
```

Depois, reinicie sua DAW e faça um novo scan de plugins, se necessário.

> O app **Standalone** pode ser aberto direto, sem instalação.

### Script do REAPER
Requer a extensão **[ReaImGui](https://github.com/cfillion/reaimgui)** (disponível via ReaPack).

**Via ReaPack (recomendado):**
1. No REAPER: **Extensions → ReaPack → Import repositories...**
2. Cole a URL:
   ```
   https://github.com/afonsorek/Little-Things/raw/main/index.xml
   ```
3. Em **Extensions → ReaPack → Browse packages**, procure por **Little Things** e instale.

**Manual:**

```bash
bash "REAPER Script/install_reaper.sh"
```

Ou carregue o `.lua` manualmente em **Actions → Show action list → New action → Load ReaScript**.

---

## 🚀 Como usar

1. Conecte o **Launchpad MK3** via USB.
2. Adicione o plugin **Little Things** na track de áudio.
3. Capture o áudio:
   - **Com ARA:** clique em **CAPTURAR TRACK (ARA 2)**.
   - **Sem ARA:** clique em **ARM (PLAY TO RENDER)**, dê play na DAW e clique em **FINALIZAR RENDER**.
4. Escolha o modo de fatiamento (Transientes, Grade ou Igualitário).
5. Clique em **Cortar em 16 Pads** (ou 8, 32, 64).
6. Pronto — o Launchpad acende e já está pronto para tocar! 🎶

---

## 📋 Requisitos

- macOS
- Novation Launchpad MK3 (Mini / X / Pro)
- DAW com suporte a VST3 ou AU (ARA 2 opcional) — ou REAPER com ReaImGui

---

## 📄 Licença

Veja o arquivo [LICENSE](LICENSE).
