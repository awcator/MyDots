# WhatsApp MCP — operator ping/call stack

Claude (via MCP) messages and voice-calls the operator's phone. Two Go binaries
plus two local TTS wrappers.

## Pieces

| Path | What |
|---|---|
| `main.go` → `wa` | WhatsApp messenger/caller (whatsmeow). Recipient is **compiled in** (`defaultRecipient`). |
| `mcp/main.go` → `mcp/wa-mcp` | MCP stdio server. Tools: `send_message`, `send_image`, `send_file`, `call`. Spawns `wa`. Tool descriptions load into every Claude session's context — keep them SHORT. |
| `kokoro-tts` + `kokoro/`, `kokoro-venv/` | Local TTS wrapper #1 (fast, ~4 s, no emotion). CLI mimics `edge-tts`. |
| `chatterbox-tts` + `chatterbox-venv/`, `voices/` | Local TTS wrapper #2 (default; ~25 s, emotional). Chatterbox-Turbo, CPU. `--text` supports `[laugh] [chuckle] [sigh] [cough]` — they render as real sounds. Voices are clone references: drop a `.wav` into `voices/`, it becomes selectable. `voices/nova.wav` = operator's chosen voice. |

MCP config lives in `~/.claude.json` → `mcpServers.whatsapp`:
`WA_BIN` (defaults to this dir's `wa`), `TTS_BIN` (default `edge-tts`; set to
`…/chatterbox-tts`), `TTS_VOICE` (=`nova`), optional `TTS_EXAG`.

## Phone number — the landmine

Repo keeps `defaultRecipient = "91xxxxxxxxx"` (placeholder, never commit the
real number). **Building without swapping in the real number sends the bot's
messages to the literal string "91xxxxxxxxx" — silently.**

Build + deploy (number goes in, then out):

```bash
cd ~/.claude/mcp-servers/whatapp
sed -i 's/91xxxxxxxxx/<REAL_NUMBER>/' main.go
go build -o wa . && cp -f wa ~/bin/wa && cp -f wa ./wa   # ~/bin/wa is what the operator uses; ./wa is WA_BIN
cd mcp && go build -o wa-mcp .                            # no number in this one
cd .. && sed -i 's/<REAL_NUMBER>/91xxxxxxxxx/' main.go    # revert!
~/bin/wa send "wa rebuilt $(date)"                        # smoke test
```

`wa` session/auth: `~/.local/share/wa/whatsapp.db`.

## Voices — what the community actually loves (researched 2026-10-29)

Chatterbox has **no named voice library** — the voice is whatever reference
clip you pass (`audio_prompt_path`, ~5-15 s clean mono). What people love in
the wild (HN thread 44251411 "Chatterbox TTS", 188 comments; HF Space
ResembleAI/Chatterbox, the viral demo):

- **"The Chatterbox voice"** everyone knows = **Jennifer English** (pro VA,
  voice of Maelle in Clair Obscur: Expedition 33). Resemble shipped her sample
  as the Space's default reference (`conds.pt` in the Turbo/model repos — the
  voice you get when NO reference is passed). If someone says "that lovely
  calm female voice Chatterbox demos use", this is it.
- **Own-voice cloning** is the #1 hands-on use (upload 10 s of yourself).
- **Audiobook/podcast narration** is the favorite workload: clean long-form
  narration clips make the best references; community verdict "best voice
  cloning available locally by far", and the common split is Kokoro for fast
  bulk reading, Chatterbox for expressive/cloned speech.
- **#1 failure mode: accent bleed** — reference clip language must match the
  language tag, or output inherits the clip's accent.
- Turbo's README signature demo = a phone-support persona ("Sarah here from
  MochaFone [chuckle]") — calm phone-agent references suit call bots.

## Mood tags — all 19 (extracted from Turbo's tokenizer, the authoritative list)

`[whispering] [sigh] [groan] [crying] [sniff] [laugh] [chuckle] [gasp]`
`[surprised] [happy] [angry] [fear] [sarcastic] [dramatic] [narration]`
`[advertisement] [shush] [cough] [clear throat]`

Embed inline in `--text`/call text; they render as real non-verbal sounds or
tonal shifts, never spoken as words. The full list also lives in the `call`
tool description so any Claude session sees the menu. Moaning ≈
`[groan]`/`[sigh]`; intimate ≈ `[whispering]`; `[narration]`/`[dramatic]`
change delivery style globally for that stretch of text.

Current call voice: **`nova`** (`voices/nova.wav`) — Kokoro af_nova line
cloned by Turbo; this is the "yes awesome" voice the user approved.
`voices/ja.wav` (Japanese-accent English from the user's video) explored and
REJECTED for calls ("i dont want japanese") — kept as alternate.
Hard-won rules: do NOT raise exaggeration/temperature — both went robotic;
personality/cuteness comes from how the TEXT is written. Turbo rushes long
paragraphs — keep call texts to 3-6 sentences. `--speed` (env `TTS_SPEED`,
ffmpeg atempo) exists if a voice inherits a too-fast ref; Nova needs 1.0.

## Model & links

- Chatterbox family (Resemble AI, MIT): <https://github.com/resemble-ai/chatterbox>
  - Turbo (350 M, English, paralinguistic tags — what we run):
    <https://huggingface.co/ResembleAI/chatterbox-turbo> · demo Space
    <https://huggingface.co/spaces/ResembleAI/chatterbox-turbo-demo>
  - Flagship 0.5 B (exaggeration dial): <https://huggingface.co/ResembleAI/chatterbox>
  - Multilingual V3 (23 langs): <https://huggingface.co/spaces/ResembleAI/Chatterbox-Multilingual-TTS-V3>
  - Overview: <https://www.resemble.ai/learn/models/chatterbox-turbo>
- Kokoro-82M (Apache-2.0, our fast fallback): code
  <https://github.com/thewh1teagle/kokoro-onnx> · weights
  <https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX> · voices
  (named, community favorites: `af_heart`, `af_nova`, `af_sky`, `am_michael`)
  per-voice `.bin` in that weights repo.
- pip: `pip install Chatterbox-TTS` / `pip install kokoro-onnx soundfile`
- CPU wheels: <https://download.pytorch.org/whl/cpu>

## TTS notes (all CPU-only — this box has no GPU)

- `edge-tts` (pip, online) occasionally 403s when Microsoft rotates the
  `Sec-MS-GEC` token; fix = `tts-venv/bin/pip install -U edge-tts`.
- Chatterbox base model reads `[laugh]` as the word *laugh* — only **Turbo**
  (`tts_turbo.ChatterboxTurboTTS`) renders tags natively. `--exaggeration` is
  ignored by Turbo.
- Both wrappers output mp3 via ffmpeg (drop-in for wa-mcp's edge-tts CLI call:
  `--voice --text --write-media`).
