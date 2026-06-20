# Modelfile Reference

Complete reference for Ollama Modelfile syntax, parameters, templates, and Python integration.

## Modelfile Syntax

A Modelfile is a blueprint for creating and customizing Ollama models. It uses a Dockerfile-like syntax with the following instructions:

### Instructions Overview

| Instruction | Description | Required |
|-------------|-------------|----------|
| `FROM` | Base model or adapter to build from | Yes |
| `PARAMETER` | Set model runtime parameters | No |
| `TEMPLATE` | Chat template using Go template syntax | No |
| `SYSTEM` | Default system message | No |
| `ADAPTER` | Apply a LoRA or QLoRA adapter | No |
| `LICENSE` | Specify the model license | No |
| `MESSAGE` | Seed conversation history | No |

### FROM

Specifies the base model. This is the only required instruction.

```dockerfile
# From an Ollama model tag
FROM llama3.1:8b-instruct-q5_K_M

# From a specific digest
FROM llama3.1@sha256:abcdef1234567890

# From a local GGUF file
FROM ./my-model.gguf
```

### PARAMETER

Sets runtime parameters that control model behavior during inference.

```dockerfile
PARAMETER temperature 0.7
PARAMETER top_p 0.9
PARAMETER num_ctx 4096
```

### TEMPLATE

Defines the chat template using Go template syntax. This controls how messages are formatted before being sent to the model.

```dockerfile
TEMPLATE """
{{- if .System }}<|start_header_id|>system<|end_header_id|>

{{ .System }}<|eot_id|>
{{- end }}
{{- range .Messages }}
<|start_header_id|>{{ .Role }}<|end_header_id|>

{{ .Content }}<|eot_id|>
{{- end }}<|start_header_id|>assistant<|end_header_id|>

"""
```

### SYSTEM

Sets the default system message for the model.

```dockerfile
SYSTEM """
You are a senior Python developer. You write clean, well-tested code.
You always include type hints and docstrings. You prefer standard library
solutions over third-party packages when possible.
"""
```

### ADAPTER

Applies a LoRA or QLoRA adapter to the base model.

```dockerfile
FROM llama3.1:8b
ADAPTER ./fine-tuned-adapter.gguf
```

### LICENSE

Specifies the license for the custom model.

```dockerfile
LICENSE """
MIT License
Copyright (c) 2024
"""
```

### MESSAGE

Seeds the conversation with example messages to guide model behavior.

```dockerfile
MESSAGE user "What is the capital of France?"
MESSAGE assistant "The capital of France is Paris."
```

## Parameters Reference

### Complete Parameter List

| Parameter | Type | Default | Range | Description |
|-----------|------|---------|-------|-------------|
| `temperature` | float | 0.8 | 0.0 - 2.0 | Controls randomness. Lower = more deterministic. |
| `top_p` | float | 0.9 | 0.0 - 1.0 | Nucleus sampling threshold. Lower = more focused. |
| `top_k` | int | 40 | 1 - 100+ | Limits token candidates. Lower = more focused. |
| `repeat_penalty` | float | 1.1 | 0.0 - 2.0 | Penalizes repeated tokens. Higher = less repetition. |
| `repeat_last_n` | int | 64 | 0 - num_ctx | Window size for repeat penalty. 0 = disabled. |
| `num_ctx` | int | 2048 | 512 - 131072 | Context window size in tokens. Affects VRAM usage. |
| `num_predict` | int | -1 | -2 - inf | Max tokens to generate. -1 = infinite, -2 = fill context. |
| `stop` | string | - | - | Stop sequence. Model stops generating when this is produced. |
| `seed` | int | 0 | any | Random seed for reproducibility. 0 = random. |
| `num_gpu` | int | auto | 0 - N | Number of GPU layers to offload. 0 = CPU only. |
| `num_thread` | int | auto | 1 - N | Number of CPU threads for inference. |
| `mirostat` | int | 0 | 0, 1, 2 | Mirostat sampling. 0 = disabled, 1 = v1, 2 = v2. |
| `mirostat_tau` | float | 5.0 | 0.0 - 10.0 | Target entropy for Mirostat. Lower = more focused. |
| `mirostat_eta` | float | 0.1 | 0.0 - 1.0 | Learning rate for Mirostat. |
| `tfs_z` | float | 1.0 | 0.0 - 2.0 | Tail free sampling. 1.0 = disabled. |
| `num_keep` | int | 0 | 0+ | Number of tokens to keep from initial prompt on context overflow. |
| `typical_p` | float | 1.0 | 0.0 - 1.0 | Typical sampling threshold. 1.0 = disabled. |
| `presence_penalty` | float | 0.0 | -2.0 - 2.0 | Penalizes tokens based on presence in text so far. |
| `frequency_penalty` | float | 0.0 | -2.0 - 2.0 | Penalizes tokens based on frequency in text so far. |

### Recommended Parameter Presets by Task

#### Code Generation

```dockerfile
PARAMETER temperature 0.2
PARAMETER top_p 0.85
PARAMETER top_k 20
PARAMETER repeat_penalty 1.1
PARAMETER num_ctx 8192
PARAMETER num_predict 2048
PARAMETER stop "<|eot_id|>"
```

**Rationale**: Low temperature for deterministic output. Moderate top_p/top_k to allow some variation in coding style without randomness. Large context for reading source files. Repeat penalty prevents repetitive code blocks.

#### Conversational Chat

```dockerfile
PARAMETER temperature 0.7
PARAMETER top_p 0.9
PARAMETER top_k 40
PARAMETER repeat_penalty 1.15
PARAMETER num_ctx 4096
PARAMETER num_predict -1
```

**Rationale**: Moderate temperature for natural-sounding responses. Higher top_p/top_k for varied vocabulary. Slightly higher repeat penalty to avoid conversational loops.

#### RAG (Retrieval-Augmented Generation)

```dockerfile
PARAMETER temperature 0.1
PARAMETER top_p 0.8
PARAMETER top_k 10
PARAMETER repeat_penalty 1.05
PARAMETER num_ctx 8192
PARAMETER num_predict 1024
```

**Rationale**: Very low temperature for factual accuracy. Low top_k to stay focused on retrieved context. Large context window to accommodate retrieved documents. Limited prediction length to keep answers concise.

#### Structured Output (JSON)

```dockerfile
PARAMETER temperature 0.0
PARAMETER top_p 1.0
PARAMETER repeat_penalty 1.0
PARAMETER num_ctx 4096
PARAMETER num_predict 2048
```

**Rationale**: Zero temperature for completely deterministic output. No repeat penalty since JSON naturally has repeated keys. Full top_p to avoid cutting off valid JSON tokens.

## Template Syntax for Chat Models

### Go Template Variables

| Variable | Description |
|----------|-------------|
| `{{ .System }}` | System message content |
| `{{ .Prompt }}` | User prompt (non-chat mode) |
| `{{ .Response }}` | Model response (non-chat mode) |
| `{{ .Messages }}` | Array of chat messages |
| `{{ .Message.Role }}` | Message role (system, user, assistant) |
| `{{ .Message.Content }}` | Message content |

### Llama 3 / Llama 3.1 Template

```dockerfile
TEMPLATE """
{{- if .System }}<|start_header_id|>system<|end_header_id|>

{{ .System }}<|eot_id|>
{{- end }}
{{- range .Messages }}
<|start_header_id|>{{ .Role }}<|end_header_id|>

{{ .Content }}<|eot_id|>
{{- end }}<|start_header_id|>assistant<|end_header_id|>

"""
```

### Mistral / Mixtral Template

```dockerfile
TEMPLATE """
{{- if .System }}[INST] {{ .System }}
{{ end }}
{{- range .Messages }}
{{- if eq .Role "user" }}[INST] {{ .Content }} [/INST]
{{- else }}{{ .Content }}</s>
{{- end }}
{{- end }}
"""
```

### Phi-3 Template

```dockerfile
TEMPLATE """
{{- if .System }}<|system|>
{{ .System }}<|end|>
{{- end }}
{{- range .Messages }}
<|{{ .Role }}|>
{{ .Content }}<|end|>
{{- end }}
<|assistant|>
"""
```

### Gemma 2 Template

```dockerfile
TEMPLATE """
{{- if .System }}<start_of_turn>user
{{ .System }}
<end_of_turn>
{{- end }}
{{- range .Messages }}
<start_of_turn>{{ .Role }}
{{ .Content }}<end_of_turn>
{{- end }}
<start_of_turn>model
"""
```

### ChatML Template (Qwen, many fine-tunes)

```dockerfile
TEMPLATE """
{{- if .System }}<|im_start|>system
{{ .System }}<|im_end|>
{{- end }}
{{- range .Messages }}
<|im_start|>{{ .Role }}
{{ .Content }}<|im_end|>
{{- end }}
<|im_start|>assistant
"""
```

## SYSTEM Prompt Best Practices

### Principles

1. **Be specific about the role**: "You are a Python code reviewer" not "You are helpful"
2. **State constraints explicitly**: "Respond only in JSON" or "Do not include explanations"
3. **Keep it concise**: Long system prompts consume context window and may be partially ignored
4. **Test the boundary**: Verify the model respects the system prompt with adversarial inputs
5. **Avoid contradictions**: "Be concise" and "provide detailed explanations" conflict

### Example: Coding Assistant

```dockerfile
SYSTEM """
You are a senior Python developer and code reviewer.

Rules:
- Write Python 3.10+ code with type hints on all function signatures
- Include docstrings for all public functions and classes
- Prefer standard library solutions over third-party packages
- Follow PEP 8 naming conventions
- When reviewing code, list issues by severity: critical, warning, info
- Never apologize or use filler phrases
"""
```

### Example: RAG Assistant

```dockerfile
SYSTEM """
You are a technical documentation assistant. You answer questions using ONLY
the provided context. If the context does not contain the answer, say
"I don't have enough information to answer that."

Rules:
- Cite the source document when answering
- Do not make up information not present in the context
- Keep answers concise (under 200 words unless asked for detail)
- Use code blocks for any code snippets
"""
```

### Example: Structured Output

```dockerfile
SYSTEM """
You extract structured data from text. Always respond with valid JSON.
Never include text outside the JSON object. Follow the schema exactly
as specified in the user prompt.
"""
```

## Complete Modelfile Examples

### Coding Assistant (Llama 3.1 8B)

```dockerfile
FROM llama3.1:8b-instruct-q5_K_M

# Low temperature for deterministic code generation
PARAMETER temperature 0.2
PARAMETER top_p 0.85
PARAMETER top_k 20
PARAMETER repeat_penalty 1.1
PARAMETER num_ctx 8192
PARAMETER num_predict 2048
PARAMETER stop "<|eot_id|>"

SYSTEM """
You are a senior software engineer specializing in Python and TypeScript.

Rules:
- Write clean, production-ready code with type annotations
- Include error handling for all I/O operations
- Write docstrings for public APIs
- Prefer async/await for I/O-bound operations
- When asked to review, provide specific line-level feedback
"""
```

### Chat Companion (Phi-3)

```dockerfile
FROM phi3:14b-medium-4k-instruct-q4_K_M

PARAMETER temperature 0.7
PARAMETER top_p 0.9
PARAMETER top_k 40
PARAMETER repeat_penalty 1.15
PARAMETER num_ctx 4096
PARAMETER num_predict -1

SYSTEM """
You are a knowledgeable and thoughtful conversational assistant.
Be concise and direct. Ask clarifying questions when the request
is ambiguous. Admit when you are unsure rather than guessing.
"""
```

### RAG Document QA (Mistral)

```dockerfile
FROM mistral:7b-instruct-v0.3-q5_K_M

PARAMETER temperature 0.1
PARAMETER top_p 0.8
PARAMETER top_k 10
PARAMETER repeat_penalty 1.05
PARAMETER num_ctx 8192
PARAMETER num_predict 1024

SYSTEM """
You answer questions based solely on the provided context documents.
If the context does not contain the answer, state that clearly.
Always cite the relevant section or document. Keep answers factual
and concise.
"""
```

### JSON Extractor (Qwen 2.5)

```dockerfile
FROM qwen2.5:7b-instruct-q5_K_M

PARAMETER temperature 0.0
PARAMETER top_p 1.0
PARAMETER repeat_penalty 1.0
PARAMETER num_ctx 4096
PARAMETER num_predict 2048

SYSTEM """
You extract structured data from text. Always respond with valid JSON only.
No markdown, no explanation, no text outside the JSON object. Follow the
schema provided in each request exactly.
"""
```

### Multi-Stage Build with Adapter

```dockerfile
FROM llama3.1:8b
ADAPTER ./my-lora-adapter.gguf

PARAMETER temperature 0.3
PARAMETER num_ctx 4096

SYSTEM """
You are a domain-specific assistant fine-tuned for medical terminology
extraction. Extract all medical terms and their relationships from the
provided text.
"""
```

## Python Integration (ollama-python)

### Installation

```bash
pip install ollama
```

### Basic Usage

```python
import ollama


def chat_with_model(model: str, prompt: str, system: str = "") -> str:
    """Send a chat message and return the response."""
    messages = []
    if system:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": prompt})

    response = ollama.chat(model=model, messages=messages)
    return response["message"]["content"]


def stream_chat(model: str, prompt: str) -> None:
    """Stream a chat response token by token."""
    messages = [{"role": "user", "content": prompt}]
    stream = ollama.chat(model=model, messages=messages, stream=True)

    for chunk in stream:
        content = chunk["message"]["content"]
        print(content, end="", flush=True)
    print()
```

### Creating Models from Modelfile

```python
import ollama
from pathlib import Path


def create_model_from_file(model_name: str, modelfile_path: str) -> None:
    """Create an Ollama model from a Modelfile on disk."""
    modelfile_content = Path(modelfile_path).read_text()
    create_model(model_name, modelfile_content)


def create_model(model_name: str, modelfile: str) -> None:
    """Create an Ollama model from a Modelfile string."""
    print(f"Creating model '{model_name}'...")
    for progress in ollama.create(model=model_name, modelfile=modelfile, stream=True):
        status = progress.get("status", "")
        completed = progress.get("completed", 0)
        total = progress.get("total", 0)
        if total:
            pct = (completed / total) * 100
            print(f"\r  {status}: {pct:.1f}%", end="", flush=True)
        else:
            print(f"\r  {status}", end="", flush=True)
    print(f"\nModel '{model_name}' created successfully.")


def create_coding_assistant() -> None:
    """Create a coding assistant model with optimized parameters."""
    modelfile = """
FROM llama3.1:8b-instruct-q5_K_M

PARAMETER temperature 0.2
PARAMETER top_p 0.85
PARAMETER num_ctx 8192
PARAMETER stop "<|eot_id|>"

SYSTEM \"\"\"
You are a senior Python developer. Write clean, typed, tested code.
\"\"\"
"""
    create_model("coding-assistant", modelfile)
```

### Listing and Managing Models

```python
import ollama


def list_models() -> list[dict]:
    """List all locally available Ollama models."""
    response = ollama.list()
    models = []
    for model in response["models"]:
        models.append({
            "name": model["name"],
            "size_gb": round(model["size"] / (1024 ** 3), 2),
            "modified": model["modified_at"],
            "family": model.get("details", {}).get("family", "unknown"),
            "parameter_size": model.get("details", {}).get("parameter_size", "unknown"),
            "quantization": model.get("details", {}).get("quantization_level", "unknown"),
        })
    return models


def show_model_info(model_name: str) -> dict:
    """Show detailed information about a model."""
    info = ollama.show(model_name)
    return {
        "modelfile": info.get("modelfile", ""),
        "parameters": info.get("parameters", ""),
        "template": info.get("template", ""),
        "system": info.get("system", ""),
        "details": info.get("details", {}),
    }


def pull_model(model_name: str) -> None:
    """Pull a model from the Ollama registry with progress."""
    print(f"Pulling model '{model_name}'...")
    for progress in ollama.pull(model=model_name, stream=True):
        status = progress.get("status", "")
        completed = progress.get("completed", 0)
        total = progress.get("total", 0)
        if total:
            pct = (completed / total) * 100
            print(f"\r  {status}: {pct:.1f}%", end="", flush=True)
        else:
            print(f"\r  {status}", end="", flush=True)
    print(f"\nModel '{model_name}' pulled successfully.")


def delete_model(model_name: str) -> None:
    """Delete a locally stored model."""
    ollama.delete(model_name)
    print(f"Model '{model_name}' deleted.")
```

### Embeddings

```python
import ollama


def get_embedding(model: str, text: str) -> list[float]:
    """Get the embedding vector for a text string."""
    response = ollama.embeddings(model=model, prompt=text)
    return response["embedding"]


def get_batch_embeddings(model: str, texts: list[str]) -> list[list[float]]:
    """Get embedding vectors for multiple texts."""
    embeddings = []
    for text in texts:
        response = ollama.embeddings(model=model, prompt=text)
        embeddings.append(response["embedding"])
    return embeddings
```

## Ollama CLI Commands Reference

### Model Management

```bash
# Pull a model from the registry
ollama pull llama3.1:8b-instruct-q5_K_M

# List all local models
ollama list

# Show model details (parameters, template, system prompt)
ollama show llama3.1:8b-instruct-q5_K_M

# Show just the Modelfile
ollama show llama3.1:8b-instruct-q5_K_M --modelfile

# Remove a model
ollama rm my-custom-model

# Copy a model (create alias)
ollama cp llama3.1:8b-instruct-q5_K_M my-llama

# Push a model to the registry (requires account)
ollama push username/my-model
```

### Running Models

```bash
# Interactive chat
ollama run llama3.1:8b-instruct-q5_K_M

# Single prompt (non-interactive)
ollama run llama3.1:8b-instruct-q5_K_M "Explain Python generators"

# With system prompt override
ollama run llama3.1:8b-instruct-q5_K_M --system "You are a pirate." "Tell me about Python"
```

### Creating Custom Models

```bash
# Create from a Modelfile
ollama create my-coding-model -f ./Modelfile

# Create from a Modelfile in a specific directory
ollama create my-rag-model -f ./modelfiles/rag-assistant.Modelfile
```

### Server Management

```bash
# Start the Ollama server (if not running as a service)
ollama serve

# Check running models
ollama ps

# Check version
ollama --version

# Set custom host/port
OLLAMA_HOST=0.0.0.0:11434 ollama serve

# Set custom model storage directory
OLLAMA_MODELS=/path/to/models ollama serve
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OLLAMA_HOST` | `127.0.0.1:11434` | Bind address for the server |
| `OLLAMA_MODELS` | `~/.ollama/models` | Model storage directory |
| `OLLAMA_KEEP_ALIVE` | `5m` | How long to keep models loaded |
| `OLLAMA_NUM_PARALLEL` | `1` | Number of parallel requests |
| `OLLAMA_MAX_LOADED_MODELS` | `1` | Max models loaded simultaneously |
| `OLLAMA_GPU_OVERHEAD` | `0` | Reserved GPU memory (bytes) |
| `HTTPS_PROXY` | - | Proxy for model downloads |

## Using the REST API Directly with httpx

For advanced use cases or when the Python library does not expose a feature:

```python
import httpx
import json


OLLAMA_BASE_URL = "http://localhost:11434"


def generate_raw(model: str, prompt: str, options: dict | None = None) -> str:
    """Generate a response using the raw /api/generate endpoint."""
    payload = {
        "model": model,
        "prompt": prompt,
        "stream": False,
    }
    if options:
        payload["options"] = options

    response = httpx.post(
        f"{OLLAMA_BASE_URL}/api/generate",
        json=payload,
        timeout=120.0,
    )
    response.raise_for_status()
    return response.json()["response"]


def chat_raw(model: str, messages: list[dict], options: dict | None = None) -> dict:
    """Chat using the raw /api/chat endpoint."""
    payload = {
        "model": model,
        "messages": messages,
        "stream": False,
    }
    if options:
        payload["options"] = options

    response = httpx.post(
        f"{OLLAMA_BASE_URL}/api/chat",
        json=payload,
        timeout=120.0,
    )
    response.raise_for_status()
    return response.json()


def stream_generate(model: str, prompt: str) -> None:
    """Stream a generation response using httpx."""
    payload = {
        "model": model,
        "prompt": prompt,
        "stream": True,
    }

    with httpx.stream(
        "POST",
        f"{OLLAMA_BASE_URL}/api/generate",
        json=payload,
        timeout=120.0,
    ) as response:
        response.raise_for_status()
        for line in response.iter_lines():
            if line:
                data = json.loads(line)
                token = data.get("response", "")
                print(token, end="", flush=True)
                if data.get("done", False):
                    break
    print()


def list_models_raw() -> list[dict]:
    """List models using the REST API."""
    response = httpx.get(f"{OLLAMA_BASE_URL}/api/tags", timeout=30.0)
    response.raise_for_status()
    return response.json().get("models", [])
```
