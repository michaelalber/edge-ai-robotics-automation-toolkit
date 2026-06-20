# Chunking Strategies for RAG Pipelines

## Overview

Chunking is the process of splitting documents into segments suitable for embedding and retrieval. The choice of chunking strategy directly impacts retrieval quality -- it is the single most influential design decision in a RAG pipeline after embedding model selection.

**Key Tradeoffs:**
- **Smaller chunks** = more precise retrieval, but may lose surrounding context
- **Larger chunks** = more context preserved, but may dilute relevance and exceed embedding model limits
- **More overlap** = smoother boundary transitions, but increases index size and embedding cost
- **Less overlap** = smaller index, but risks losing information at chunk boundaries

## Chunk Size Guidelines

| Embedding Model | Max Tokens | Recommended Chunk Size (chars) | Recommended Overlap (chars) |
|----------------|------------|-------------------------------|----------------------------|
| all-MiniLM-L6-v2 | 256 | 800-900 | 150-200 |
| all-mpnet-base-v2 | 384 | 1200-1400 | 200-300 |
| nomic-embed-text | 8192 | 1000-2000 | 200-400 |
| mxbai-embed-large | 512 | 1600-1800 | 300-400 |
| text-embedding-3-small | 8191 | 1000-2000 | 200-400 |
| text-embedding-3-large | 8191 | 1000-2000 | 200-400 |

**Rule of thumb:** Target 80-90% of the embedding model's token limit in characters (assuming ~4 chars/token for English). Leave margin for tokenizer overhead.

---

## Strategy 1: Fixed-Size Chunking with Overlap

The simplest strategy. Split text into fixed character-length chunks with a sliding overlap window.

**When to use:** Quick prototyping, uniform-length documents, when you need predictable chunk sizes.

**When to avoid:** Documents with strong structural boundaries (headings, sections) that should be preserved.

### LangChain Implementation

```python
from langchain.text_splitter import CharacterTextSplitter


def fixed_size_chunking(
    documents: list,
    chunk_size: int = 1000,
    chunk_overlap: int = 200,
) -> list:
    """Split documents into fixed-size chunks with overlap.

    Args:
        documents: List of LangChain Document objects.
        chunk_size: Maximum characters per chunk.
        chunk_overlap: Number of overlapping characters between consecutive chunks.

    Returns:
        List of chunked Document objects with preserved metadata.
    """
    splitter = CharacterTextSplitter(
        separator="\n",
        chunk_size=chunk_size,
        chunk_overlap=chunk_overlap,
        length_function=len,
    )
    chunks = splitter.split_documents(documents)
    print(f"Fixed-size: {len(documents)} docs -> {len(chunks)} chunks")
    return chunks
```

### LlamaIndex Implementation

```python
from llama_index.core.node_parser import SentenceSplitter


def fixed_size_chunking_llamaindex(
    documents: list,
    chunk_size: int = 1024,
    chunk_overlap: int = 200,
) -> list:
    """Split documents into fixed-size chunks using LlamaIndex.

    Args:
        documents: List of LlamaIndex Document objects.
        chunk_size: Maximum characters per chunk.
        chunk_overlap: Number of overlapping characters between chunks.

    Returns:
        List of TextNode objects.
    """
    parser = SentenceSplitter(
        chunk_size=chunk_size,
        chunk_overlap=chunk_overlap,
    )
    nodes = parser.get_nodes_from_documents(documents)
    print(f"Fixed-size (LlamaIndex): {len(documents)} docs -> {len(nodes)} nodes")
    return nodes
```

---

## Strategy 2: Recursive Character Text Splitting

Splits text hierarchically using a list of separators, trying the most semantically meaningful separator first (paragraphs, then sentences, then words). This is the **recommended default** for most use cases.

**When to use:** General-purpose chunking, prose documents, when you want chunks that respect natural text boundaries.

**When to avoid:** Highly structured documents where explicit structure (headings, code blocks) should drive the split.

### LangChain Implementation

```python
from langchain.text_splitter import RecursiveCharacterTextSplitter


def recursive_chunking(
    documents: list,
    chunk_size: int = 1000,
    chunk_overlap: int = 200,
) -> list:
    """Split documents using recursive character splitting.

    Tries separators in order: double newline, single newline, sentence
    boundary, space, then character-level as a last resort.

    Args:
        documents: List of LangChain Document objects.
        chunk_size: Maximum characters per chunk.
        chunk_overlap: Number of overlapping characters.

    Returns:
        List of chunked Document objects.
    """
    splitter = RecursiveCharacterTextSplitter(
        chunk_size=chunk_size,
        chunk_overlap=chunk_overlap,
        length_function=len,
        separators=["\n\n", "\n", ". ", " ", ""],
    )
    chunks = splitter.split_documents(documents)

    # Log chunk size distribution
    sizes = [len(c.page_content) for c in chunks]
    print(f"Recursive: {len(documents)} docs -> {len(chunks)} chunks")
    print(f"  Avg size: {sum(sizes) / len(sizes):.0f} chars")
    print(f"  Min/Max: {min(sizes)}/{max(sizes)} chars")
    return chunks


def recursive_chunking_markdown(
    documents: list,
    chunk_size: int = 1000,
    chunk_overlap: int = 200,
) -> list:
    """Split Markdown documents respecting heading hierarchy.

    Separators are ordered to preserve Markdown structure:
    headings first, then paragraphs, then sentences.
    """
    splitter = RecursiveCharacterTextSplitter(
        chunk_size=chunk_size,
        chunk_overlap=chunk_overlap,
        length_function=len,
        separators=[
            "\n## ",     # H2 headings
            "\n### ",    # H3 headings
            "\n#### ",   # H4 headings
            "\n\n",      # Paragraphs
            "\n",        # Lines
            ". ",        # Sentences
            " ",         # Words
            "",          # Characters
        ],
    )
    chunks = splitter.split_documents(documents)
    print(f"Markdown recursive: {len(documents)} docs -> {len(chunks)} chunks")
    return chunks
```

### LlamaIndex Implementation

```python
from llama_index.core.node_parser import SentenceSplitter


def recursive_chunking_llamaindex(
    documents: list,
    chunk_size: int = 1024,
    chunk_overlap: int = 200,
) -> list:
    """Split documents using LlamaIndex's sentence-aware splitter.

    SentenceSplitter in LlamaIndex performs recursive splitting
    with sentence boundary awareness by default.
    """
    parser = SentenceSplitter(
        chunk_size=chunk_size,
        chunk_overlap=chunk_overlap,
        paragraph_separator="\n\n",
    )
    nodes = parser.get_nodes_from_documents(documents)
    print(f"Recursive (LlamaIndex): {len(documents)} docs -> {len(nodes)} nodes")
    return nodes
```

---

## Strategy 3: Semantic Chunking

Groups sentences by semantic similarity using embeddings. Adjacent sentences with similar embeddings stay together; a new chunk starts when the semantic similarity drops below a threshold.

**When to use:** Dense prose where topic shifts are gradual, academic papers, long-form articles.

**When to avoid:** Short documents, documents with clear structural markers, when embedding cost is a concern (this strategy embeds every sentence individually).

### LangChain Implementation

```python
from langchain_experimental.text_splitter import SemanticChunker
from langchain_community.embeddings import HuggingFaceEmbeddings


def semantic_chunking(
    documents: list,
    embedding_model: str = "all-MiniLM-L6-v2",
    breakpoint_threshold_type: str = "percentile",
    breakpoint_threshold_amount: float = 90.0,
) -> list:
    """Split documents by semantic similarity between sentences.

    Sentences with high semantic similarity are grouped together.
    A new chunk starts when similarity drops below the threshold.

    Args:
        documents: List of LangChain Document objects.
        embedding_model: Sentence-transformers model for similarity computation.
        breakpoint_threshold_type: How to determine chunk boundaries.
            "percentile" -- break at the Nth percentile of distances.
            "standard_deviation" -- break when distance exceeds mean + N*std.
            "interquartile" -- break at IQR-based outlier distances.
        breakpoint_threshold_amount: Threshold value (meaning depends on type).

    Returns:
        List of semantically chunked Document objects.
    """
    embeddings = HuggingFaceEmbeddings(
        model_name=embedding_model,
        model_kwargs={"device": "cuda"},
        encode_kwargs={"normalize_embeddings": True},
    )

    splitter = SemanticChunker(
        embeddings=embeddings,
        breakpoint_threshold_type=breakpoint_threshold_type,
        breakpoint_threshold_amount=breakpoint_threshold_amount,
    )

    chunks = splitter.split_documents(documents)
    sizes = [len(c.page_content) for c in chunks]
    print(f"Semantic: {len(documents)} docs -> {len(chunks)} chunks")
    print(f"  Avg size: {sum(sizes) / len(sizes):.0f} chars")
    print(f"  Min/Max: {min(sizes)}/{max(sizes)} chars")
    return chunks
```

### LlamaIndex Implementation

```python
from llama_index.core.node_parser import SemanticSplitterNodeParser
from llama_index.embeddings.huggingface import HuggingFaceEmbedding


def semantic_chunking_llamaindex(
    documents: list,
    embedding_model: str = "all-MiniLM-L6-v2",
    buffer_size: int = 1,
    breakpoint_percentile_threshold: int = 95,
) -> list:
    """Split documents by semantic similarity using LlamaIndex.

    Args:
        documents: List of LlamaIndex Document objects.
        embedding_model: HuggingFace model name.
        buffer_size: Number of sentences to group for comparison.
        breakpoint_percentile_threshold: Percentile threshold for new chunks.

    Returns:
        List of TextNode objects.
    """
    embed_model = HuggingFaceEmbedding(model_name=embedding_model)

    parser = SemanticSplitterNodeParser(
        embed_model=embed_model,
        buffer_size=buffer_size,
        breakpoint_percentile_threshold=breakpoint_percentile_threshold,
    )
    nodes = parser.get_nodes_from_documents(documents)
    print(f"Semantic (LlamaIndex): {len(documents)} docs -> {len(nodes)} nodes")
    return nodes
```

---

## Strategy 4: Sentence Window Chunking

Embeds individual sentences but retrieves a window of surrounding sentences for context. The index stores single sentences (for precise matching), but the retrieval returns the sentence plus its neighbors (for context).

**When to use:** When you need precise sentence-level matching but also need surrounding context for generation.

**When to avoid:** When chunks need to be larger units of meaning (paragraphs, sections).

### LlamaIndex Implementation

```python
from llama_index.core.node_parser import SentenceWindowNodeParser
from llama_index.core import Document


def sentence_window_chunking(
    documents: list,
    window_size: int = 3,
) -> list:
    """Create sentence-window nodes for precise retrieval with context.

    Each node contains a single sentence for embedding, plus a window
    of surrounding sentences stored in metadata for context during generation.

    Args:
        documents: List of LlamaIndex Document objects.
        window_size: Number of surrounding sentences to include in the window.

    Returns:
        List of TextNode objects with window metadata.
    """
    parser = SentenceWindowNodeParser.from_defaults(
        window_size=window_size,
        window_metadata_key="window",
        original_text_metadata_key="original_text",
    )
    nodes = parser.get_nodes_from_documents(documents)
    print(f"Sentence window: {len(documents)} docs -> {len(nodes)} nodes")
    print(f"  Window size: {window_size} sentences on each side")
    return nodes
```

### Manual Implementation (Framework-Agnostic)

```python
import re
from dataclasses import dataclass


@dataclass
class SentenceWindowChunk:
    """A chunk containing a single sentence with a surrounding context window."""
    sentence: str           # The target sentence (used for embedding)
    window: str             # The sentence plus surrounding context (used for generation)
    source: str             # Source document identifier
    sentence_index: int     # Position within the document


def split_into_sentences(text: str) -> list[str]:
    """Split text into sentences using regex."""
    sentences = re.split(r'(?<=[.!?])\s+', text.strip())
    return [s.strip() for s in sentences if s.strip()]


def sentence_window_chunking_manual(
    text: str,
    source: str = "unknown",
    window_size: int = 3,
) -> list[SentenceWindowChunk]:
    """Create sentence-window chunks manually.

    Args:
        text: Raw document text.
        source: Document source identifier.
        window_size: Number of surrounding sentences for context.

    Returns:
        List of SentenceWindowChunk objects.
    """
    sentences = split_into_sentences(text)
    chunks = []

    for i, sentence in enumerate(sentences):
        start = max(0, i - window_size)
        end = min(len(sentences), i + window_size + 1)
        window = " ".join(sentences[start:end])

        chunks.append(SentenceWindowChunk(
            sentence=sentence,
            window=window,
            source=source,
            sentence_index=i,
        ))

    print(f"Sentence window (manual): {len(sentences)} sentences -> {len(chunks)} chunks")
    return chunks
```

---

## Strategy 5: Document-Type-Specific Strategies

### PDF Documents

PDFs require special handling because text extraction often introduces artifacts.

```python
from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain_community.document_loaders import PyPDFLoader
import re


def chunk_pdf(
    pdf_path: str,
    chunk_size: int = 1000,
    chunk_overlap: int = 200,
) -> list:
    """Load and chunk a PDF with preprocessing.

    Handles common PDF extraction artifacts:
    - Page headers and footers
    - Page numbers
    - Hyphenated line breaks
    - Excessive whitespace
    """
    loader = PyPDFLoader(pdf_path)
    pages = loader.load()

    # Preprocess each page
    for page in pages:
        text = page.page_content

        # Fix hyphenated line breaks (e.g., "computa-\ntion" -> "computation")
        text = re.sub(r"(\w)-\n(\w)", r"\1\2", text)

        # Remove page numbers
        text = re.sub(r"\n\s*\d+\s*\n", "\n", text)

        # Normalize whitespace
        text = re.sub(r"[ \t]+", " ", text)
        text = re.sub(r"\n{3,}", "\n\n", text)

        page.page_content = text.strip()

    # Add page number to metadata
    for i, page in enumerate(pages):
        page.metadata["page_number"] = i + 1

    splitter = RecursiveCharacterTextSplitter(
        chunk_size=chunk_size,
        chunk_overlap=chunk_overlap,
        separators=["\n\n", "\n", ". ", " ", ""],
    )
    chunks = splitter.split_documents(pages)
    print(f"PDF chunking: {pdf_path} -> {len(chunks)} chunks from {len(pages)} pages")
    return chunks
```

### Markdown Documents

Markdown has inherent structure (headings, lists, code blocks) that should be preserved.

```python
from langchain.text_splitter import MarkdownHeaderTextSplitter, RecursiveCharacterTextSplitter


def chunk_markdown(
    text: str,
    chunk_size: int = 1000,
    chunk_overlap: int = 200,
    source: str = "unknown",
) -> list:
    """Chunk Markdown preserving heading hierarchy in metadata.

    First splits by headers to capture section context,
    then applies recursive splitting for size control.
    """
    # Step 1: Split by Markdown headers
    headers_to_split_on = [
        ("#", "h1"),
        ("##", "h2"),
        ("###", "h3"),
        ("####", "h4"),
    ]
    header_splitter = MarkdownHeaderTextSplitter(
        headers_to_split_on=headers_to_split_on,
        strip_headers=False,
    )
    header_chunks = header_splitter.split_text(text)

    # Step 2: Further split large sections
    recursive_splitter = RecursiveCharacterTextSplitter(
        chunk_size=chunk_size,
        chunk_overlap=chunk_overlap,
        separators=["\n\n", "\n", ". ", " ", ""],
    )
    final_chunks = recursive_splitter.split_documents(header_chunks)

    # Enrich metadata
    for chunk in final_chunks:
        chunk.metadata["source"] = source
        # Build section path from header metadata
        section_parts = []
        for key in ["h1", "h2", "h3", "h4"]:
            if key in chunk.metadata:
                section_parts.append(chunk.metadata[key])
        if section_parts:
            chunk.metadata["section_path"] = " > ".join(section_parts)

    print(f"Markdown chunking: {len(header_chunks)} sections -> {len(final_chunks)} chunks")
    return final_chunks
```

### Source Code

Code requires language-aware splitting that respects function/class boundaries.

```python
from langchain.text_splitter import (
    RecursiveCharacterTextSplitter,
    Language,
)


def chunk_code(
    code: str,
    language: Language = Language.PYTHON,
    chunk_size: int = 1500,
    chunk_overlap: int = 200,
    source: str = "unknown",
) -> list:
    """Chunk source code using language-aware splitting.

    Respects function, class, and block boundaries for the given language.

    Supported languages: Python, JavaScript, TypeScript, Java, Go, Rust,
    C, C++, C#, Ruby, PHP, Scala, Swift, and more.
    """
    splitter = RecursiveCharacterTextSplitter.from_language(
        language=language,
        chunk_size=chunk_size,
        chunk_overlap=chunk_overlap,
    )

    from langchain_core.documents import Document
    doc = Document(page_content=code, metadata={"source": source, "language": language.value})
    chunks = splitter.split_documents([doc])

    print(f"Code chunking ({language.value}): 1 file -> {len(chunks)} chunks")
    return chunks


# Example: Chunk Python code
python_code = '''
class Calculator:
    """A simple calculator class."""

    def add(self, a: float, b: float) -> float:
        """Add two numbers."""
        return a + b

    def subtract(self, a: float, b: float) -> float:
        """Subtract b from a."""
        return a - b

    def multiply(self, a: float, b: float) -> float:
        """Multiply two numbers."""
        return a * b

    def divide(self, a: float, b: float) -> float:
        """Divide a by b."""
        if b == 0:
            raise ValueError("Cannot divide by zero")
        return a / b
'''

chunks = chunk_code(python_code, Language.PYTHON, chunk_size=500, chunk_overlap=50)
for i, chunk in enumerate(chunks):
    print(f"Chunk {i}: {len(chunk.page_content)} chars")
    print(chunk.page_content[:100])
    print("---")
```

---

## Strategy 6: Parent-Child (Hierarchical) Chunking

Index small chunks for precise retrieval but return their parent (larger) chunk for context. Combines the precision of small chunks with the context richness of large chunks.

### LlamaIndex Implementation

```python
from llama_index.core.node_parser import HierarchicalNodeParser, SentenceSplitter
from llama_index.core.storage.docstore import SimpleDocumentStore
from llama_index.core.retrievers import AutoMergingRetriever


def hierarchical_chunking(
    documents: list,
    chunk_sizes: list[int] = None,
) -> tuple:
    """Create a parent-child chunk hierarchy.

    Small leaf nodes are used for retrieval; if enough leaf nodes
    from the same parent are retrieved, the parent is returned instead.

    Args:
        documents: List of LlamaIndex Document objects.
        chunk_sizes: List of chunk sizes from largest to smallest.
            Default: [2048, 512, 128] (3-level hierarchy).

    Returns:
        Tuple of (all_nodes, leaf_nodes, docstore).
    """
    if chunk_sizes is None:
        chunk_sizes = [2048, 512, 128]

    parser = HierarchicalNodeParser.from_defaults(
        chunk_sizes=chunk_sizes,
    )
    nodes = parser.get_nodes_from_documents(documents)

    # Separate leaf nodes (smallest chunks) for indexing
    leaf_nodes = [n for n in nodes if not n.child_nodes]

    # Store all nodes in docstore for parent lookup
    docstore = SimpleDocumentStore()
    docstore.add_documents(nodes)

    print(f"Hierarchical: {len(documents)} docs -> {len(nodes)} total nodes")
    print(f"  Leaf nodes (for indexing): {len(leaf_nodes)}")
    print(f"  Levels: {len(chunk_sizes)}, sizes: {chunk_sizes}")
    return nodes, leaf_nodes, docstore
```

---

## Chunk Size Optimization

### Empirical Testing Framework

The best chunk size depends on your specific corpus and queries. Use this framework to find the optimal size.

```python
from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain_community.embeddings import HuggingFaceEmbeddings
from langchain_chroma import Chroma
import time


def benchmark_chunk_sizes(
    documents: list,
    test_queries: list[dict],
    chunk_sizes: list[int],
    overlap_ratio: float = 0.2,
    embedding_model: str = "all-MiniLM-L6-v2",
    top_k: int = 5,
) -> list[dict]:
    """Benchmark retrieval quality across different chunk sizes.

    Args:
        documents: Source documents to chunk and index.
        test_queries: List of {"query": str, "expected_sources": list[str]}.
        chunk_sizes: List of chunk sizes to test.
        overlap_ratio: Overlap as a fraction of chunk size.
        embedding_model: Embedding model name.
        top_k: Number of results to retrieve.

    Returns:
        List of benchmark results per chunk size.
    """
    embeddings = HuggingFaceEmbeddings(
        model_name=embedding_model,
        encode_kwargs={"normalize_embeddings": True},
    )

    results = []

    for chunk_size in chunk_sizes:
        overlap = int(chunk_size * overlap_ratio)
        print(f"\nTesting chunk_size={chunk_size}, overlap={overlap}")

        # Chunk
        splitter = RecursiveCharacterTextSplitter(
            chunk_size=chunk_size,
            chunk_overlap=overlap,
        )
        chunks = splitter.split_documents(documents)

        # Index
        start = time.time()
        vectorstore = Chroma.from_documents(
            documents=chunks,
            embedding=embeddings,
            collection_name=f"bench_{chunk_size}",
        )
        index_time = time.time() - start

        # Evaluate retrieval
        retriever = vectorstore.as_retriever(search_kwargs={"k": top_k})
        precision_scores = []

        for tq in test_queries:
            retrieved = retriever.invoke(tq["query"])
            sources = [d.metadata.get("source", "") for d in retrieved]
            relevant = sum(1 for s in sources if s in tq["expected_sources"])
            precision_scores.append(relevant / top_k)

        avg_precision = sum(precision_scores) / len(precision_scores)

        result = {
            "chunk_size": chunk_size,
            "overlap": overlap,
            "num_chunks": len(chunks),
            "index_time_sec": round(index_time, 2),
            "avg_precision_at_k": round(avg_precision, 3),
        }
        results.append(result)
        print(f"  Chunks: {len(chunks)}, Precision@{top_k}: {avg_precision:.3f}")

        # Cleanup
        vectorstore.delete_collection()

    # Print comparison table
    print("\n" + "=" * 70)
    print(f"{'Chunk Size':>12} {'Overlap':>8} {'Chunks':>8} {'Index(s)':>10} {'P@k':>8}")
    print("-" * 70)
    for r in results:
        print(
            f"{r['chunk_size']:>12} "
            f"{r['overlap']:>8} "
            f"{r['num_chunks']:>8} "
            f"{r['index_time_sec']:>10.2f} "
            f"{r['avg_precision_at_k']:>8.3f}"
        )

    return results
```

### Recommended Starting Points by Document Type

| Document Type | Chunk Size | Overlap | Rationale |
|--------------|-----------|---------|-----------|
| Technical docs (Markdown) | 1000-1500 | 200-300 | Sections are self-contained, moderate size preserves context |
| Academic papers (PDF) | 800-1200 | 150-250 | Dense prose, paragraphs are meaningful units |
| Legal documents | 1500-2000 | 300-400 | Clauses reference surrounding text, need more context |
| Code files | 1000-2000 | 100-200 | Functions/classes are natural boundaries, less overlap needed |
| Chat logs / Q&A | 500-800 | 100-150 | Individual exchanges are short, need less context |
| Product descriptions | 300-600 | 50-100 | Short, self-contained items |

---

## Testing Chunking Quality

Always validate chunking output before proceeding to embedding.

```python
def validate_chunks(chunks: list, min_size: int = 50, max_size: int = 2000) -> dict:
    """Validate chunk quality and report issues.

    Args:
        chunks: List of Document or TextNode objects.
        min_size: Minimum acceptable chunk size in characters.
        max_size: Maximum acceptable chunk size in characters.

    Returns:
        Validation report dictionary.
    """
    issues = {
        "too_small": [],
        "too_large": [],
        "empty": [],
        "no_metadata": [],
    }

    for i, chunk in enumerate(chunks):
        content = chunk.page_content if hasattr(chunk, "page_content") else chunk.text
        size = len(content)

        if size == 0:
            issues["empty"].append(i)
        elif size < min_size:
            issues["too_small"].append({"index": i, "size": size, "preview": content[:80]})
        elif size > max_size:
            issues["too_large"].append({"index": i, "size": size})

        metadata = chunk.metadata if hasattr(chunk, "metadata") else {}
        if not metadata or "source" not in metadata:
            issues["no_metadata"].append(i)

    total_issues = sum(len(v) for v in issues.values())
    report = {
        "total_chunks": len(chunks),
        "total_issues": total_issues,
        "empty_chunks": len(issues["empty"]),
        "too_small": len(issues["too_small"]),
        "too_large": len(issues["too_large"]),
        "missing_metadata": len(issues["no_metadata"]),
        "details": issues,
    }

    # Print summary
    print(f"Chunk validation: {len(chunks)} chunks, {total_issues} issues")
    if issues["empty"]:
        print(f"  WARNING: {len(issues['empty'])} empty chunks")
    if issues["too_small"]:
        print(f"  WARNING: {len(issues['too_small'])} chunks below {min_size} chars")
    if issues["too_large"]:
        print(f"  WARNING: {len(issues['too_large'])} chunks above {max_size} chars")
    if issues["no_metadata"]:
        print(f"  WARNING: {len(issues['no_metadata'])} chunks missing metadata")

    return report
```

---

## Putting It All Together: Chunking Pipeline

```python
from langchain.text_splitter import RecursiveCharacterTextSplitter, Language
from langchain_community.document_loaders import (
    PyPDFLoader,
    UnstructuredMarkdownLoader,
    TextLoader,
)
from pathlib import Path
import re


class ChunkingPipeline:
    """Document-type-aware chunking pipeline.

    Routes each document to the appropriate chunking strategy
    based on file extension and content type.
    """

    def __init__(
        self,
        default_chunk_size: int = 1000,
        default_overlap: int = 200,
    ):
        self.default_chunk_size = default_chunk_size
        self.default_overlap = default_overlap

        # Strategy configuration per document type
        self.strategies = {
            ".pdf": {"chunk_size": 1000, "overlap": 200, "preprocess": True},
            ".md": {"chunk_size": 1200, "overlap": 250, "preprocess": False},
            ".txt": {"chunk_size": 1000, "overlap": 200, "preprocess": False},
            ".py": {"chunk_size": 1500, "overlap": 150, "language": Language.PYTHON},
            ".js": {"chunk_size": 1500, "overlap": 150, "language": Language.JS},
            ".ts": {"chunk_size": 1500, "overlap": 150, "language": Language.TS},
        }

    def preprocess_pdf_text(self, text: str) -> str:
        """Clean common PDF extraction artifacts."""
        text = re.sub(r"(\w)-\n(\w)", r"\1\2", text)
        text = re.sub(r"\n\s*\d+\s*\n", "\n", text)
        text = re.sub(r"[ \t]+", " ", text)
        text = re.sub(r"\n{3,}", "\n\n", text)
        return text.strip()

    def chunk_document(self, doc, file_extension: str) -> list:
        """Chunk a single document using the appropriate strategy."""
        config = self.strategies.get(file_extension, {})
        chunk_size = config.get("chunk_size", self.default_chunk_size)
        overlap = config.get("overlap", self.default_overlap)

        # Preprocess if needed
        if config.get("preprocess"):
            doc.page_content = self.preprocess_pdf_text(doc.page_content)

        # Code splitting
        if "language" in config:
            splitter = RecursiveCharacterTextSplitter.from_language(
                language=config["language"],
                chunk_size=chunk_size,
                chunk_overlap=overlap,
            )
        else:
            splitter = RecursiveCharacterTextSplitter(
                chunk_size=chunk_size,
                chunk_overlap=overlap,
                separators=["\n\n", "\n", ". ", " ", ""],
            )

        return splitter.split_documents([doc])

    def process(self, documents: list) -> list:
        """Process a list of documents through the chunking pipeline.

        Routes each document to the appropriate strategy based on its
        source file extension.
        """
        all_chunks = []

        for doc in documents:
            source = doc.metadata.get("source", "")
            ext = Path(source).suffix.lower() if source else ".txt"
            chunks = self.chunk_document(doc, ext)
            all_chunks.extend(chunks)

        print(f"ChunkingPipeline: {len(documents)} docs -> {len(all_chunks)} chunks")
        return all_chunks


# Usage
pipeline = ChunkingPipeline(default_chunk_size=1000, default_overlap=200)
# chunks = pipeline.process(documents)
```

---

## Quick Reference: When to Use Which Strategy

| Strategy | Best For | Complexity | Quality | Cost |
|----------|---------|-----------|---------|------|
| Fixed-size | Prototyping, uniform docs | Low | Medium | Low |
| Recursive | General-purpose (default) | Low | High | Low |
| Semantic | Dense prose, topic detection | Medium | Highest | Medium |
| Sentence window | Precise matching + context | Medium | High | Medium |
| Markdown-aware | Structured docs | Low | High | Low |
| Code-aware | Source code | Low | High | Low |
| Hierarchical | Multi-granularity retrieval | High | Highest | High |
