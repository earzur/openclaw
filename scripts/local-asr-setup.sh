#!/bin/bash
# OpenClaw Local ASR Setup Script
#
# Installs antirez's Pure C implementation of Qwen3-ASR
# for fast, private, offline speech-to-text transcription.
#
# Credits:
#   - Qwen3-ASR Model: Alibaba Qwen Team (Apache 2.0)
#     https://github.com/QwenLM/Qwen3-ASR
#   - C Implementation: Salvatore Sanfilippo (antirez) (BSD-2-Clause)
#     https://github.com/antirez/qwen-asr
#
# Usage:
#   ./scripts/local-asr-setup.sh [small|large]
#
# Arguments:
#   small  - Install Qwen3-ASR-0.6B (~1.8GB) - default
#   large  - Install Qwen3-ASR-1.7B (~3.5GB)

set -e

INSTALL_DIR="${OPENCLAW_LOCAL_ASR_DIR:-$HOME/.openclaw/local-asr}"
REPO_URL="https://github.com/antirez/qwen-asr.git"
MODEL_SIZE="${1:-small}"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  OpenClaw Local ASR Setup                                    ║"
echo "║                                                              ║"
echo "║  Using antirez/qwen-asr (BSD-2-Clause)                       ║"
echo "║  Model: Qwen3-ASR by Alibaba Qwen Team (Apache 2.0)          ║"
echo "║                                                              ║"
echo "║  Disk space required:                                        ║"
echo "║    • small (0.6B): ~2GB                                      ║"
echo "║    • large (1.7B): ~4GB                                      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Detect OS
OS="$(uname -s)"
ARCH="$(uname -m)"
echo "→ Platform: $OS ($ARCH)"

# Check dependencies
check_deps() {
    local missing=()

    command -v gcc &>/dev/null || missing+=("gcc")
    command -v make &>/dev/null || missing+=("make")
    command -v git &>/dev/null || missing+=("git")
    command -v curl &>/dev/null || missing+=("curl")
    command -v ffmpeg &>/dev/null || missing+=("ffmpeg")

    # Check BLAS on Linux
    if [ "$OS" = "Linux" ]; then
        BLAS_FOUND=0
        pkg-config --exists openblas 2>/dev/null && BLAS_FOUND=1
        [ -f /usr/include/openblas/cblas.h ] && BLAS_FOUND=1
        [ -f /usr/include/cblas.h ] && BLAS_FOUND=1
        # Ubuntu/Debian puts headers in arch-specific path
        [ -f /usr/include/x86_64-linux-gnu/openblas-pthread/cblas.h ] && BLAS_FOUND=1
        [ -f /usr/include/aarch64-linux-gnu/openblas-pthread/cblas.h ] && BLAS_FOUND=1
        # Also check if the library exists
        [ -f /usr/lib/x86_64-linux-gnu/libopenblas.so ] && BLAS_FOUND=1
        [ -f /usr/lib/aarch64-linux-gnu/libopenblas.so ] && BLAS_FOUND=1
        
        if [ "$BLAS_FOUND" = "0" ]; then
            missing+=("libopenblas-dev")
        fi
    fi

    if [ ${#missing[@]} -ne 0 ]; then
        echo "✗ Missing dependencies: ${missing[*]}"
        echo ""
        if [ "$OS" = "Linux" ]; then
            echo "  Install with:"
            echo "    sudo apt-get install -y ${missing[*]}"
        elif [ "$OS" = "Darwin" ]; then
            echo "  Install with:"
            echo "    xcode-select --install"
            echo "    brew install ffmpeg"
        fi
        exit 1
    fi

    echo "✓ Dependencies OK"
}

# Clone or update repository
clone_repo() {
    echo ""
    echo "→ Fetching antirez/qwen-asr..."

    if [ -d "$INSTALL_DIR/src/.git" ]; then
        echo "  Updating existing clone..."
        cd "$INSTALL_DIR/src"
        git fetch origin
        git reset --hard origin/master || git reset --hard origin/main
    else
        mkdir -p "$INSTALL_DIR"
        rm -rf "$INSTALL_DIR/src"
        git clone --depth 1 "$REPO_URL" "$INSTALL_DIR/src"
    fi

    echo "✓ Source ready"
}

# Build binary
build() {
    echo ""
    echo "→ Building qwen_asr..."

    cd "$INSTALL_DIR/src"

    make clean 2>/dev/null || true

    if [ "$OS" = "Darwin" ]; then
        make  # Uses Accelerate framework
    else
        make blas  # Uses OpenBLAS
    fi

    cp qwen_asr "$INSTALL_DIR/"

    echo "✓ Build complete"
}

# Download model
download_model() {
    echo ""

    if [ "$MODEL_SIZE" = "large" ]; then
        MODEL_NAME="qwen3-asr-1.7b"
        MODEL_HF="Qwen/Qwen3-ASR-1.7B"
        MODEL_SIZE_HUMAN="~3.5GB (total ~4GB with source)"
    else
        MODEL_NAME="qwen3-asr-0.6b"
        MODEL_HF="Qwen/Qwen3-ASR-0.6B"
        MODEL_SIZE_HUMAN="~1.8GB (total ~2GB with source)"
    fi

    MODEL_DIR="$INSTALL_DIR/$MODEL_NAME"

    if [ -f "$MODEL_DIR/model.safetensors" ]; then
        echo "→ Model already present: $MODEL_NAME"
        echo "✓ Skipping download"
        return
    fi

    echo "→ Downloading $MODEL_HF ($MODEL_SIZE_HUMAN)..."

    mkdir -p "$MODEL_DIR"
    cd "$MODEL_DIR"

    BASE_URL="https://huggingface.co/$MODEL_HF/resolve/main"
    FILES="config.json generation_config.json model.safetensors vocab.json merges.txt"

    for f in $FILES; do
        if [ ! -f "$f" ]; then
            echo "  ↓ $f"
            curl -L -o "$f" "$BASE_URL/$f" --progress-bar
        fi
    done

    echo "✓ Model downloaded"
}

# Create wrapper script
create_wrapper() {
    echo ""
    echo "→ Creating transcribe.sh wrapper..."

    cat > "$INSTALL_DIR/transcribe.sh" << 'WRAPPER'
#!/bin/bash
# OpenClaw Local ASR - Transcription wrapper
# Credits: antirez/qwen-asr (BSD-2-Clause)

AUDIO="$1"
LANG="${2:-}"
DIR="$(dirname "$(realpath "$0")")"
MODEL="${OPENCLAW_ASR_MODEL:-qwen3-asr-0.6b}"

[ -z "$AUDIO" ] && { echo "Usage: $0 <audio_file> [language]" >&2; exit 1; }

MODEL_PATH="$DIR/$MODEL"
[ ! -d "$MODEL_PATH" ] && { echo "Model not found: $MODEL_PATH" >&2; exit 1; }

TMP_WAV=$(mktemp /tmp/openclaw_asr_XXXXXX.wav)
trap "rm -f $TMP_WAV" EXIT

ffmpeg -y -i "$AUDIO" -ar 16000 -ac 1 "$TMP_WAV" 2>/dev/null

LANG_OPT=""
[ -n "$LANG" ] && LANG_OPT="--language $LANG"

"$DIR/qwen_asr" -d "$MODEL_PATH" -i "$TMP_WAV" --silent $LANG_OPT
WRAPPER

    chmod +x "$INSTALL_DIR/transcribe.sh"
    echo "✓ Wrapper created"
}

# Verify installation
verify() {
    echo ""
    echo "→ Verifying installation..."

    if [ ! -x "$INSTALL_DIR/qwen_asr" ]; then
        echo "✗ Binary not executable"
        exit 1
    fi

    # Quick sanity check
    "$INSTALL_DIR/qwen_asr" --help >/dev/null 2>&1 || true

    echo "✓ Installation verified"
}

# Summary
summary() {
    if [ "$MODEL_SIZE" = "large" ]; then
        MODEL_NAME="qwen3-asr-1.7b"
    else
        MODEL_NAME="qwen3-asr-0.6b"
    fi

    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  ✓ Local ASR installed successfully!                         ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Location: $INSTALL_DIR"
    echo "Model:    $MODEL_NAME"
    echo ""
    echo "Usage:"
    echo "  $INSTALL_DIR/transcribe.sh <audio_file> [language]"
    echo ""
    echo "OpenClaw config (openclaw.json):"
    echo '  "tools": {'
    echo '    "media": {'
    echo '      "audio": {'
    echo '        "models": [{'
    echo '          "provider": "local-asr",'
    echo "          \"model\": \"$MODEL_NAME\""
    echo '        }]'
    echo '      }'
    echo '    }'
    echo '  }'
    echo ""
    echo "Credits:"
    echo "  • antirez/qwen-asr: https://github.com/antirez/qwen-asr"
    echo "  • Qwen3-ASR: https://github.com/QwenLM/Qwen3-ASR"
    echo ""
}

# Main
main() {
    check_deps
    clone_repo
    build
    download_model
    create_wrapper
    verify
    summary
}

main
