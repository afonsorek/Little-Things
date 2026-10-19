# Little Things — Launchpad Chop Engine

**Little Things** transforma qualquer trecho de áudio em um kit pronto para tocar no **Novation Launchpad**. O script captura o áudio da sua track, divide em fatias e distribui cada uma em um pad, com as cores acesas no próprio Launchpad.

Feito como **script para o REAPER**.

---

## ✨ Recursos

- ✂️ **Fatiamento automático**: o trecho é dividido em fatias de tamanho igual.
- 🟩 **8, 16, 32 ou 64 pads**: as fatias vão direto para o Launchpad.
- 🌈 **Feedback visual**: cada pad acende com a cor da sua fatia.
- 💾 **Presets de kits** (`.ltkit`): salve e recarregue seus kits quando quiser.

---

## 📋 Requisitos

- **REAPER 7** ou superior
- Extensão **[ReaImGui](https://github.com/cfillion/reaimgui)** (instalável pelo ReaPack)
- **Novation Launchpad MK3**

---

## 🛠️ Instalação

### Via ReaPack (recomendado)

1. No REAPER, abra **Extensions → ReaPack → Import repositories...**
2. Cole a URL:
   ```
   https://github.com/afonsorek/Little-Things/raw/main/index.xml
   ```
3. Em **Extensions → ReaPack → Browse packages**, procure por **Little Things** e instale.

### Manualmente

1. Copie a pasta `REAPER Script/` para a pasta de scripts do REAPER.
2. Em **Actions → Show action list → New action → Load ReaScript**, selecione o arquivo `Little Things - Launchpad Chop Engine.lua`.

---

## 🚀 Como usar

1. Conecte o Launchpad via USB.
2. Em **Options → Preferences → Audio → MIDI Devices**, ative o Launchpad como **entrada** e como **saída**.
3. Rode o script **Little Things** pela lista de ações.
4. Nas configurações do script, selecione o **MIDI In** e o **MIDI Out** do Launchpad.
5. Pronto: o Launchpad acende e já dá para tocar. 🎶

---

## 📦 Estrutura

```
REAPER Script/
├── Little Things - Launchpad Chop Engine.lua   # Script principal (ReaImGui)
├── Little Things/
│   ├── LittleThings_MIDI_Bridge.jsfx           # Ponte MIDI entre o REAPER e o Launchpad
│   └── Presets/                                # Kits de exemplo (.ltkit)
└── install_reaper.sh                           # Instalador para o REAPER
```

---

## 👥 Créditos

Desenvolvido por **Erick** e **Afonso**.

## 📄 Licença

Veja o arquivo [LICENSE](LICENSE).
