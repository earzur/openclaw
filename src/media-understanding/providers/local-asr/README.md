# Local ASR Provider

Fast, private, offline speech-to-text transcription using [Qwen3-ASR](https://github.com/QwenLM/Qwen3-ASR) via [antirez's Pure C implementation](https://github.com/antirez/qwen-asr).

## Credits

- **Qwen3-ASR Model**: [Alibaba Qwen Team](https://github.com/QwenLM/Qwen3-ASR) (Apache 2.0)
- **C Implementation**: [Salvatore Sanfilippo (antirez)](https://github.com/antirez/qwen-asr) (BSD-2-Clause)

## Why Local ASR?

| Feature | Cloud APIs | Local ASR |
|---------|------------|-----------|
| Privacy | Audio sent to cloud | Stays on device |
| Latency | Network round-trip | ~3-5s for 5s audio |
| Cost | Per-minute billing | Free |
| Offline | No | Yes |

## Installation

```bash
./scripts/local-asr-setup.sh [small|large]
```

Options:
- `small` (default): Qwen3-ASR-0.6B (~1.8GB)
- `large`: Qwen3-ASR-1.7B (~3.5GB)

### Requirements

**Linux:**
```bash
sudo apt-get install -y gcc make git curl ffmpeg libopenblas-dev
```

**macOS:**
```bash
xcode-select --install
brew install ffmpeg
```

## Configuration

```json
{
  "tools": {
    "media": {
      "audio": {
        "models": [{
          "provider": "local-asr",
          "model": "qwen3-asr-0.6b"
        }]
      }
    }
  }
}
```

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `model` | `qwen3-asr-0.6b` | Model size |
| `language` | auto | Force language (e.g., `French`) |

## Performance

Benchmarks on Intel i5-12450H (CPU-only):

| System | Time (5s audio) | Quality |
|--------|-----------------|---------|
| Whisper base | 9.5s | "bit coin" |
| Qwen3-ASR 0.6B | 3.7s | "Bitcoin" ✓ |

## License

This provider wrapper: MIT  
antirez/qwen-asr: BSD-2-Clause  
Qwen3-ASR model: Apache 2.0
