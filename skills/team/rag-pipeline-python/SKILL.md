---
name: rag-pipeline-python
audience: team
description: >
  Scaffold RAG pipelines with Ollama or cloud embeddings. Use when building
  retrieval-augmented generation systems with local or cloud LLMs, vector stores,
  and document processing. Do NOT use when the application stack is .NET — use
  rag-pipeline-dotnet instead; do NOT use for full-text search without semantic
  retrieval requirements.
---

# RAG Pipeline Scaffold

> "The quality of your RAG system is bounded by the quality of your retrieval, not the quality of your generation model."
> -- Jerry Liu, creator of LlamaIndex

## Core Philosophy

This skill scaffolds end-to-end Retrieval-Augmented Generation pipelines: document ingestion, chunking, embedding, indexing, retrieval, generation, and evaluation. Every design decision is grounded in **retrieval quality** and **measurable relevance**.

**Non-Negotiable Constraints:**
1. Retrieval quality MUST be measured before generation is tuned — garbage in, garbage out
2. Chunk size and overlap MUST be chosen deliberately based on corpus type and embedding model context window
3. Every pipeline MUST include an evaluation step with representative queries before deployment
4. Embedding model selection MUST account for dimensionality, speed, and domain fit
5. Document preprocessing MUST be validated — never embed raw, unparsed content with formatting artifacts

## Domain Principles Table

| # | Principle | Description | Priority |
|---|-----------|-------------|----------|
| 1 | **Retrieval Precision** | Retrieved chunks must be relevant to the query. Measure precision@k and MRR before tuning generation. Irrelevant context degrades output quality more than no context. | Critical |
| 2 | **Chunk Coherence** | Each chunk must be a self-contained unit of meaning. A chunk that starts mid-sentence or splits a code block is worse than a slightly larger chunk that preserves boundaries. | Critical |
| 3 | **Embedding Quality** | The embedding model determines the ceiling of retrieval performance. Evaluate on domain-specific queries, not just general benchmarks. | Critical |
| 4 | **Context Window Awareness** | Total retrieved context plus prompt must fit within the generation model's context window. Calculate token budgets explicitly. | High |
| 5 | **Document Preprocessing** | Strip noise while preserving semantic content. Validate by spot-checking chunks. | High |
| 6 | **Metadata Enrichment** | Every chunk should carry metadata: source document, page/section, creation date, document type. Enables filtered retrieval and source attribution. | High |
| 7 | **Index Freshness** | Stale indexes produce stale answers. Define an update strategy and document the refresh cadence. | Medium |
| 8 | **Query Transformation** | Raw user queries are often poor retrieval queries. Consider query expansion, HyDE, or multi-query retrieval to improve recall. | Medium |
| 9 | **Answer Grounding** | Generated answers MUST cite their source chunks. Hallucinated answers without grounding are the primary RAG failure mode. | Critical |
| 10 | **Cost Awareness** | Estimate costs per query and per corpus re-index before committing to a design. | Medium |
| 11 | **Incremental Ingestion** | For corpora > 100 documents, use hash-based change detection to skip unchanged files. Track chunk IDs per document to delete stale chunks on re-ingest — stale chunks are invisible failures. | High |

## Knowledge Base Lookups

| Query | When to Call |
|-------|--------------|
| `search_knowledge("RAG retrieval augmented generation chunking strategy")` | During CHUNK phase — ground chunk size and boundary decisions |
| `search_knowledge("embedding model selection sentence transformers")` | During EMBED phase — verify model selection and context window limits |
| `search_knowledge("vector store chromadb qdrant pgvector comparison")` | During INDEX phase — ground vector store selection |
| `search_knowledge("retrieval precision recall MRR evaluation metrics")` | During EVALUATE phase — confirm quality metrics and thresholds |
| `search_knowledge("LangChain document loader text splitter")` | During INGEST phase — verify LangChain API patterns |
| `search_knowledge("RAG hallucination grounding citation source attribution")` | During GENERATE phase — verify prompt engineering for grounded generation |
| `search_knowledge("python async context manager resource lifecycle")` | When implementing async pipeline components |

Search before choosing chunking strategies, embedding models, and vector stores. Cite the source path in the Pipeline Scaffold Report.

## Workflow

The pipeline flows through seven phases: **INGEST → CHUNK → EMBED → INDEX → RETRIEVE → GENERATE → EVALUATE**. If evaluation metrics fall below thresholds, iterate on the earlier phases (most likely chunking or embedding) before tuning generation. Never skip evaluation before deployment.

**Pre-flight checklist:** corpus identified (type, size, format) · sample documents for testing · hardware assessed (GPU/CPU, RAM) · embedding model selected · vector store selected · generation model selected · representative test queries drafted · success criteria defined (precision@k target).

### Step 1: INGEST — Document Loading

```python
from langchain_community.document_loaders import PyPDFLoader, UnstructuredMarkdownLoader, TextLoader, DirectoryLoader

def ingest_documents(source_dir: str) -> list:
    loaders = {"*.pdf": PyPDFLoader, "*.md": UnstructuredMarkdownLoader, "*.txt": TextLoader}
    all_docs = []
    for glob_pattern, loader_cls in loaders.items():
        loader = DirectoryLoader(source_dir, glob=glob_pattern, loader_cls=loader_cls, show_progress=True)
        all_docs.extend(loader.load())
    return all_docs
```

Spot-check 3–5 documents after ingestion to confirm text extraction preserved semantic content.
For corpora > 100 documents, add hash-based change detection to avoid reprocessing unchanged files — see [Production Ingestion Hardening](references/production-ingestion.md).

### Step 2: CHUNK — Text Splitting

Choose strategy by corpus type: structured docs (Markdown, HTML) → recursive splitting with type-specific separators; dense prose (PDF, articles) → semantic chunking or recursive (1000 chars, 200 overlap); source code → `CodeTextSplitter`; short docs under one page → embed whole documents.

```python
from langchain.text_splitter import RecursiveCharacterTextSplitter

def chunk_documents(docs: list, chunk_size: int = 1000, chunk_overlap: int = 200) -> list:
    splitter = RecursiveCharacterTextSplitter(
        chunk_size=chunk_size, chunk_overlap=chunk_overlap,
        length_function=len, separators=["\n\n", "\n", ". ", " ", ""],
    )
    return splitter.split_documents(docs)
```

See [Chunking Strategies](references/chunking-strategies.md) for detailed implementations per document type.

### Step 3: EMBED — Generate Embeddings

Local (privacy/air-gapped): `sentence-transformers` (`all-MiniLM-L6-v2`, `all-mpnet-base-v2`) or Ollama (`nomic-embed-text`, `mxbai-embed-large`). Cloud: OpenAI `text-embedding-3-small/large`, Cohere `embed-v3`. Multilingual: `paraphrase-multilingual-MiniLM-L12-v2`.

```python
from langchain_community.embeddings import HuggingFaceEmbeddings
from langchain_ollama import OllamaEmbeddings

def get_local_embeddings(model_name: str = "all-MiniLM-L6-v2"):
    return HuggingFaceEmbeddings(
        model_name=model_name, model_kwargs={"device": "cuda"},
        encode_kwargs={"normalize_embeddings": True, "batch_size": 64},
    )

def get_ollama_embeddings(model_name: str = "nomic-embed-text"):
    return OllamaEmbeddings(model=model_name)
```

### Step 4: INDEX — Store in Vector Database

```python
from langchain_chroma import Chroma

def index_chunks(chunks: list, embeddings, persist_directory: str = "./chroma_db") -> Chroma:
    return Chroma.from_documents(
        documents=chunks, embedding=embeddings,
        persist_directory=persist_directory, collection_name="rag_collection",
    )
```

See [Vector Store Patterns](references/vector-store-patterns.md) for ChromaDB, FAISS, Qdrant, and pgvector setup.

### Step 5: RETRIEVE — Semantic Search

```python
def retrieve(vectorstore, query: str, top_k: int = 5) -> list:
    retriever = vectorstore.as_retriever(search_type="similarity", search_kwargs={"k": top_k})
    return retriever.invoke(query)
```

### Step 6: GENERATE — Augmented Generation

```python
from langchain_ollama import ChatOllama
from langchain_core.prompts import ChatPromptTemplate
from langchain_core.output_parsers import StrOutputParser

def build_rag_chain(vectorstore, model_name: str = "llama3.1"):
    retriever = vectorstore.as_retriever(search_kwargs={"k": 5})
    llm = ChatOllama(model=model_name, temperature=0.1)
    prompt = ChatPromptTemplate.from_messages([
        ("system", "Answer ONLY from the provided context. Cite source documents for each claim. If context is insufficient, say so.\n\nContext:\n{context}"),
        ("human", "{question}"),
    ])
    def format_docs(docs):
        return "\n\n".join(f"[{i}] (Source: {doc.metadata.get('source', 'unknown')})\n{doc.page_content}"
                           for i, doc in enumerate(docs, 1))
    return {"context": retriever | format_docs, "question": lambda x: x} | prompt | llm | StrOutputParser()
```

### Step 7: EVALUATE — Measure Quality

```python
def evaluate_retrieval(vectorstore, test_queries: list[dict], top_k: int = 5) -> dict:
    """Each test query: {"query": "...", "expected_sources": ["doc1.pdf"]}"""
    retriever = vectorstore.as_retriever(search_kwargs={"k": top_k})
    results: dict[str, list] = {"precision_at_k": [], "recall": [], "mrr": []}
    for tq in test_queries:
        retrieved = retriever.invoke(tq["query"])
        sources = [d.metadata.get("source", "") for d in retrieved]
        relevant = sum(1 for s in sources if s in tq["expected_sources"])
        results["precision_at_k"].append(relevant / top_k)
        found = sum(1 for s in tq["expected_sources"] if s in sources)
        results["recall"].append(found / len(tq["expected_sources"]) if tq["expected_sources"] else 0)
        rr = next((1.0 / rank for rank, s in enumerate(sources, 1) if s in tq["expected_sources"]), 0.0)
        results["mrr"].append(rr)
    avg = lambda vals: sum(vals) / len(vals) if vals else 0
    return {"avg_precision_at_k": avg(results["precision_at_k"]),
            "avg_recall": avg(results["recall"]),
            "avg_mrr": avg(results["mrr"]),
            "num_queries": len(test_queries)}
```

## State Block Format

```
<rag-state>
step: [INGEST | CHUNK | EMBED | INDEX | RETRIEVE | GENERATE | EVALUATE]
corpus_type: [pdf | markdown | code | mixed]
chunking_strategy: [fixed | semantic | recursive | sentence]
embedding_model: [model name]
vector_store: [chromadb | faiss | qdrant | pgvector]
last_action: [what was just done]
next_action: [what should happen next]
blockers: [any issues]
</rag-state>
```

**Example:**
```
<rag-state>
step: EVALUATE
corpus_type: pdf
chunking_strategy: recursive
embedding_model: all-MiniLM-L6-v2
vector_store: chromadb
last_action: Built RAG chain with Ollama llama3.1
next_action: Run evaluation with 10 representative test queries
blockers: none
</rag-state>
```

## Output Templates

```markdown
## RAG Pipeline Scaffold
**Corpus**: [description, size, format] | **Embedding**: [model, local/cloud, dims]
**Vector Store**: [store, collection] | **Generation**: [model, local/cloud]

| Stage | Component | Config |
|-------|-----------|--------|
| Ingest/Chunk/Embed/Index/Retrieve/Generate | [component] | [config] |

**Dependencies**: `pip install langchain langchain-community langchain-chroma langchain-ollama sentence-transformers chromadb pypdf`
```

## AI Discipline Rules

**Always evaluate retrieval before tuning generation.** Run `evaluate_retrieval` with representative queries and verify precision@k ≥ 0.70 before adjusting prompts or model parameters. Bad retrieval cannot be compensated by better generation.

**Chunk size must match embedding model context.** Know the model's max token limit before chunking: `all-MiniLM-L6-v2` = 256 tokens (~920 chars), `nomic-embed-text` = 8192 tokens. Chunks exceeding the limit are silently truncated. Apply a 10% safety margin.

**Never skip document preprocessing.** Raw PDFs contain headers, footers, page numbers, and artifacts that degrade embedding quality. Strip noise, normalize whitespace, and validate by spot-checking chunks before indexing.

**Test with representative queries and adversarial queries before deployment.** Include at least 2 out-of-scope queries to verify the pipeline says "I don't know" rather than hallucinating. A pipeline that cannot refuse to answer will hallucinate in production.

## Anti-Patterns Table

| Anti-Pattern | Why It Fails | Correct Approach |
|--------------|-------------|------------------|
| Embedding entire documents without chunking | Exceeds embedding model context; similarity returns irrelevant noise | Chunk into coherent segments sized for the embedding model |
| One chunk size for all document types | Code needs different boundaries than prose | Use document-type-specific chunking strategies |
| Skipping retrieval evaluation | Bad retrieval → bad answers regardless of LLM | Evaluate precision@k and recall before tuning generation |
| Stuffing all retrieved chunks into context | Overfilling dilutes relevant information | Use top_k judiciously; respect token budgets |
| No metadata on chunks | Cannot filter or provide source attribution | Attach source, page, section, date to every chunk |
| Unnormalized embeddings | Inconsistent similarity scores | Use `normalize_embeddings=True` at index time |
| No preprocessing of raw documents | PDF artifacts degrade embedding quality | Preprocess and validate content before chunking |
| Splitting tables mid-row | Rows without headers (or headers without rows) are semantically useless — retrieval returns corrupt context | Detect Markdown and HTML tables before chunking; treat as atomic units |

## Error Recovery

### Low Retrieval Precision (< 0.50)
1. Inspect retrieved chunks manually for 3–5 queries
2. Try different chunk sizes (too large or too small both hurt)
3. Try a higher-quality embedding model
4. Add metadata filtering to narrow scope
5. Consider query transformation (HyDE, multi-query)

### Embedding Dimension Mismatch
1. Verify embedding model output dimension matches index configuration
2. If you changed models, rebuild the entire index
3. Common: MiniLM=384, mpnet=768, nomic-embed-text=768, OpenAI=1536/3072

### Out of Memory During Embedding
1. Reduce `batch_size` (e.g., 64 → 16)
2. Process documents in batches, persisting incrementally
3. Use CPU embeddings if GPU VRAM is insufficient

### Generation Hallucination
1. Verify system prompt explicitly says "answer ONLY from context"
2. Check whether retrieved chunks actually contain the needed information (retrieval issue)
3. Lower generation temperature (0.1 or lower for factual tasks)
4. Implement post-generation verification against source chunks

## Integration with Other Skills

- **`ollama-model-workflow`** — Use to select and benchmark embedding and generation models for the RAG pipeline. Key parameters: `nomic-embed-text` (768 dims, 8192 token context), `mxbai-embed-large` (1024 dims, higher quality). Match generation model `num_ctx` to expected retrieval context size.
- **`mcp-server-scaffold`** — Use to expose the RAG pipeline as MCP tools (`search_knowledge_base`, `ask_knowledge_base`). The pipeline becomes the backend for a knowledge retrieval MCP server.

## Reference Files

- [Chunking Strategies](references/chunking-strategies.md) — Detailed implementations for PDF, Markdown, code, and mixed content
- [Vector Store Patterns](references/vector-store-patterns.md) — Setup, CRUD, and comparisons for ChromaDB, FAISS, Qdrant, pgvector
- [Production Ingestion Hardening](references/production-ingestion.md) — Incremental ingestion, chunk lifecycle, memory-bounded batching, crash resilience, heading context, table atomicity, quality gates, sidecar pattern
