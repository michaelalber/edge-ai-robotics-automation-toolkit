# Production RAG Ingestion Hardening

Eight patterns for building ingestion pipelines that survive real corpora: incremental updates,
memory safety, structural fidelity, and crash resilience. All patterns are backend-agnostic.

---

## 1. Incremental Ingestion with Hash-Based Change Detection

Re-processing 10,000 documents every night because three changed is not a strategy. Use a
manifest file to track SHA-256 hashes and skip unchanged files.

```python
import hashlib
import json
from pathlib import Path
from dataclasses import dataclass, asdict
from datetime import datetime, timezone


@dataclass
class ManifestEntry:
    path: str
    sha256: str
    ingested_at: str
    chunk_ids: list[str]


def compute_sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(65536), b""):
            h.update(block)
    return h.hexdigest()


class IngestManifest:
    def __init__(self, manifest_path: Path):
        self._path = manifest_path
        self._entries: dict[str, ManifestEntry] = {}
        if manifest_path.exists():
            raw = json.loads(manifest_path.read_text())
            self._entries = {k: ManifestEntry(**v) for k, v in raw.items()}

    def is_changed(self, path: Path) -> bool:
        entry = self._entries.get(str(path))
        return entry is None or entry.sha256 != compute_sha256(path)

    def record(self, path: Path, chunk_ids: list[str]) -> None:
        self._entries[str(path)] = ManifestEntry(
            path=str(path),
            sha256=compute_sha256(path),
            ingested_at=datetime.now(timezone.utc).isoformat(),
            chunk_ids=chunk_ids,
        )

    def get_chunk_ids(self, path: Path) -> list[str]:
        entry = self._entries.get(str(path))
        return entry.chunk_ids if entry else []

    def save(self) -> None:
        self._path.write_text(
            json.dumps({k: asdict(v) for k, v in self._entries.items()}, indent=2)
        )
```

---

## 2. Chunk Lifecycle Management

When a document changes, stale chunks must be deleted before new ones are added. Without
deletion, both old and new chunks appear in search results — there is no error, just wrong answers.

```python
import uuid


def embed_and_store(chunks: list, vectorstore) -> list[str]:
    """Store chunks with explicit IDs. Returns IDs for the manifest."""
    chunk_ids = [str(uuid.uuid4()) for _ in chunks]
    texts = [c.page_content for c in chunks]
    metadatas = [c.metadata for c in chunks]
    vectorstore.add_texts(texts=texts, metadatas=metadatas, ids=chunk_ids)
    return chunk_ids


# Deletion API varies by vector store:
# ChromaDB:   collection.delete(ids=stale_ids)
# Qdrant:     client.delete(collection_name=..., points_selector=PointIdsList(points=stale_ids))
# pgvector:   session.execute(delete(ChunkTable).where(ChunkTable.id.in_(stale_ids)))
# FAISS:      rebuild index — FAISS does not support deletion; use Qdrant/ChromaDB for mutable corpora
```

---

## 3. Memory-Bounded Batch Streaming

Embedding 50,000 chunks requires holding all embedding vectors in memory before any are stored.
Embed a batch, store it, release it.

```python
def embed_and_store_batched(
    chunks: list,
    vectorstore,
    batch_size: int = 50,
) -> list[str]:
    all_ids: list[str] = []
    for i in range(0, len(chunks), batch_size):
        batch = chunks[i : i + batch_size]
        ids = embed_and_store(batch, vectorstore)
        all_ids.extend(ids)
        # batch goes out of scope — memory released before next batch
    return all_ids
```

**Batch size by hardware:** CPU only → 16–32 · 8 GB VRAM → 32–64 · 16+ GB VRAM → 64–128.
Start at 32 and double until OOM, then halve. For long documents (legal, technical manuals)
start lower — average chunk size is larger.

---

## 4. Crash-Resilient State Persistence

Save the manifest after every successfully processed file, not just at pipeline end. Ingesting
10,000 documents takes hours. A crash at document 9,800 should resume from 9,800.

```python
def ingest_incrementally(
    source_dir: Path,
    manifest: IngestManifest,
    vectorstore,
    batch_size: int = 50,
) -> None:
    files = [f for f in source_dir.rglob("*.*") if not should_skip(f) and manifest.is_changed(f)]
    print(f"Processing {len(files)} changed/new files")

    for file_path in files:
        try:
            stale_ids = manifest.get_chunk_ids(file_path)
            if stale_ids:
                vectorstore.delete(ids=stale_ids)

            text = get_document_text(file_path)
            if not text or not text.strip():
                continue

            chunks = chunk_document(text, metadata={"source": str(file_path)})
            chunk_ids = embed_and_store_batched(chunks, vectorstore, batch_size)

            manifest.record(file_path, chunk_ids)
            manifest.save()  # per-file save — key to crash resilience

        except Exception as e:
            print(f"Failed {file_path}: {e}")
            # No manifest.record — file retries on next run
```

---

## 5. Heading Context as Chunk Metadata

A chunk reading "Returns `None` if not found" is ambiguous. That same chunk tagged
`heading_context: ["API Reference", "UserService", "get_user"]` is precise. Heading context
improves retrieval quality and gives the LLM structural location alongside content.

```python
import re


def build_heading_index(markdown: str) -> list[tuple[int, list[str]]]:
    """Returns [(char_offset, [h1, h2, h3, ...]), ...] sorted by offset."""
    pattern = re.compile(r"^(#{1,6})\s+(.+)$", re.MULTILINE)
    stack: list[tuple[int, str]] = []  # (level, text)
    index: list[tuple[int, list[str]]] = []
    for match in pattern.finditer(markdown):
        level = len(match.group(1))
        text = match.group(2).strip()
        stack = [(lvl, t) for lvl, t in stack if lvl < level]
        stack.append((level, text))
        index.append((match.start(), [t for _, t in stack]))
    return index


def attach_heading_context(chunks: list, source_markdown: str) -> list:
    index = build_heading_index(source_markdown)
    for chunk in chunks:
        start = chunk.metadata.get("start_index", 0)
        active: list[str] = []
        for offset, headings in index:
            if offset <= start:
                active = headings
        chunk.metadata["heading_context"] = active
    return chunks
```

---

## 6. Table Atomicity

Splitting a Markdown or HTML table mid-row produces semantically useless chunks: rows without
headers, or a header row with no data. Detect tables before splitting and treat them as atomic.

```python
MARKDOWN_TABLE = re.compile(
    r"(\|.+\|\n\|[-| :]+\|\n(?:\|.+\|\n)*)",
    re.MULTILINE,
)
HTML_TABLE = re.compile(r"<table[\s\S]*?</table>", re.IGNORECASE)


def chunk_preserving_tables(text: str, splitter, metadata: dict) -> list:
    from langchain_core.documents import Document

    tables = sorted(
        [{"start": m.start(), "end": m.end(), "content": m.group()}
         for pattern in (MARKDOWN_TABLE, HTML_TABLE)
         for m in pattern.finditer(text)],
        key=lambda t: t["start"],
    )
    if not tables:
        return splitter.create_documents([text], metadatas=[metadata])

    chunks, cursor = [], 0
    for table in tables:
        if text[cursor : table["start"]].strip():
            chunks.extend(
                splitter.create_documents([text[cursor : table["start"]]], metadatas=[metadata])
            )
        chunks.append(
            Document(page_content=table["content"], metadata={**metadata, "is_table": True})
        )
        cursor = table["end"]
    if text[cursor:].strip():
        chunks.extend(splitter.create_documents([text[cursor:]], metadatas=[metadata]))
    return chunks
```

---

## 7. Pre-Flight Quality Gates

Apply before embedding to prevent OOM, noise ingestion, and wasted compute.

```python
import fnmatch

MAX_FILE_SIZE_MB = 100
EXCLUDE_FILENAMES = {
    "CHANGELOG.md", "CHANGELOG", "LICENSE", "LICENSE.md", "LICENSE.txt",
    "CODE_OF_CONDUCT.md", "CONTRIBUTING.md", "NOTICE", "NOTICE.md",
}
EXCLUDE_PATTERNS = ["CHANGELOG*", "release-notes*", "RELEASE*", "*.pdf.md"]


def should_skip(path: Path) -> str | None:
    """Returns a reason string if the file should be skipped, else None."""
    if path.name in EXCLUDE_FILENAMES:
        return f"excluded filename: {path.name}"
    for pattern in EXCLUDE_PATTERNS:
        if fnmatch.fnmatch(path.name, pattern):
            return f"excluded pattern: {pattern}"
    size_mb = path.stat().st_size / (1024 * 1024)
    if size_mb > MAX_FILE_SIZE_MB:
        return f"too large: {size_mb:.1f} MB > {MAX_FILE_SIZE_MB} MB"
    return None
```

> Add `*.pdf.md` to `EXCLUDE_PATTERNS` if using the sidecar pattern (Section 8) so sidecars
> are not re-ingested as primary sources.

---

## 8. Markdown Sidecar Pattern

PDF OCR and DOCX extraction are slow, GPU-intensive, and occasionally crash on malformed files.
Convert once, save as a `.md` sidecar, and read the sidecar on subsequent ingestions. This
decouples expensive conversion from fast incremental ingestion.

```python
def get_document_text(path: Path, converter=None) -> str:
    """Use sidecar if present; otherwise convert and cache it."""
    sidecar = path.with_suffix(path.suffix + ".md")
    if sidecar.exists():
        return sidecar.read_text(encoding="utf-8")

    if converter is None:
        return path.read_text(encoding="utf-8", errors="replace")

    text = converter.convert(path)  # expensive: OCR, layout detection
    sidecar.write_text(text, encoding="utf-8")
    return text
```

**Use sidecars for:** PDFs requiring OCR, DOCX/PPTX with complex formatting, any conversion
taking > 1 s per document.

**Skip sidecars for:** plain Markdown, RST, TXT — no conversion needed. Rapidly-changing
documents where the sidecar would be stale immediately (use hash detection to invalidate).
