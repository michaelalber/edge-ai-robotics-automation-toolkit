---
name: rag-pipeline-dotnet
audience: team
description: Implements RAG (Retrieval-Augmented Generation) pipelines using Microsoft Semantic Kernel for .NET applications with federal compliance and air-gapped deployment support. Use when building RAG .NET, Semantic Kernel RAG, vector search .NET, document QA .NET, knowledge base .NET, AI search .NET, embedding pipeline, or retrieval-augmented generation in C#.
  Do NOT use when the application stack is Python — use rag-pipeline-python
  instead; do NOT use outside federal or .NET-primary environments.
---

# RAG Pipeline (.NET / Semantic Kernel)

> "The quality of your RAG system is bounded by the quality of your retrieval, not the quality of your generation model."
> -- Jerry Liu, creator of LlamaIndex

## Core Philosophy

RAG is the primary pattern for grounding LLM responses in organizational knowledge. Rather than fine-tuning models on proprietary data, RAG retrieves relevant documents at query time and injects them as context for generation. Microsoft Semantic Kernel serves as the .NET orchestration layer, providing abstractions over embedding models, vector stores, and chat completion services.

**.NET is the right choice for RAG when:** the deployment target is an enterprise or federal environment with existing .NET infrastructure; FedRAMP/FISMA/DOE compliance mandates authorized cloud services; air-gapped or disconnected operation is required (via Ollama + local vector stores).

**Non-Negotiable Constraints:**
1. Retrieval quality MUST be measured before generation is tuned — poor retrieval means poor answers regardless of LLM
2. Chunk size and overlap MUST align with the embedding model's context window — silent truncation destroys meaning
3. Every pipeline MUST include citation and source attribution in generated responses
4. Federal deployments MUST use FIPS-compliant models and FedRAMP-authorized services
5. Document classification MUST be validated before ingestion — classified data cannot enter the RAG system

## Domain Principles Table

| # | Principle | Description | Priority |
|---|-----------|-------------|----------|
| 1 | **Retrieval Quality Over Generation Quality** | The ceiling of RAG output is set by retrieval, not generation. Measure precision@k and relevance scores before tuning prompts or switching LLMs. Irrelevant context degrades output more than no context. | Critical |
| 2 | **Chunk Size Optimization** | Chunks must be self-contained units of meaning sized to fit the embedding model's context window. Too large exceeds token limits (silent truncation). Too small loses semantic coherence. Match chunk size to corpus type and model capacity. | Critical |
| 3 | **Embedding Model Selection** | The embedding model determines the retrieval ceiling. Evaluate on domain-specific queries, not general benchmarks. See `references/embedding-models.md`. | Critical |
| 4 | **Vector Store Selection** | Choose based on deployment environment and compliance requirements. Azure AI Search for FedRAMP cloud; Qdrant or pgvector for air-gapped. See `references/vector-store-options.md`. | High |
| 5 | **Semantic + Keyword Hybrid Search** | Pure vector similarity misses exact-match queries (error codes, part numbers). Combine semantic search with BM25 when the corpus contains identifiers or technical terms. Azure AI Search supports this natively. | High |
| 6 | **Prompt Engineering for Grounded Responses** | The system prompt must constrain the LLM to answer only from provided context. Include explicit instructions to cite sources and to say "I don't know" when context is insufficient. | Critical |
| 7 | **Citation and Provenance** | Every generated answer must trace back to specific source chunks. Include document ID, section, and relevance score in the response. Required by NIST AI RMF for federal systems. | High |
| 8 | **Hallucination Detection** | Monitor for answers containing claims not present in retrieved context. Implement post-generation verification: compare answer claims against source chunk content. | High |
| 9 | **Federal Data Handling** | Validate data classification before ingestion. CUI requires access controls and audit trails. Classified data is never eligible for RAG. See `references/federal-ai-compliance.md`. | Critical |
| 10 | **Air-Gapped Deployment** | Support disconnected environments with Ollama (local LLM + embeddings) and on-premise vector stores (Qdrant, pgvector). No external API calls. | High |
| 11 | **Incremental Ingestion** | For corpora > 100 documents, use hash-based change detection to skip unchanged files. Track chunk IDs per document to delete stale chunks on re-ingest — stale chunks are invisible failures. | High |

## Knowledge Base Lookups

| Query | When to Call |
|-------|--------------|
| `search_knowledge("Semantic Kernel vector store memory connector")` | During CONFIGURE phase — verify Semantic Kernel API patterns |
| `search_knowledge("RAG retrieval augmented generation chunking embedding")` | During INGEST/CHUNK phases — ground chunk size and overlap decisions |
| `search_knowledge("vector similarity search embedding model selection")` | During INDEX phase — verify embedding model selection criteria |
| `search_knowledge("NIST AI RMF federal compliance audit logging")` | During federal deployment — verify NIST AI RMF transparency requirements |
| `search_knowledge("FedRAMP Azure Government CUI data classification")` | During federal compliance review |
| `search_knowledge("retrieval precision recall evaluation RAG metrics")` | During EVALUATE phase — confirm evaluation metrics and thresholds |
| `search_knowledge("ASP.NET Core dependency injection CancellationToken")` | During CONFIGURE phase — verify .NET DI and async patterns |

Search before configuring the pipeline, before selecting vector stores or embedding models, and before implementing federal compliance features. Cite the source in the Pipeline Configuration Summary.

## Workflow

Pipeline phases flow: **CONFIGURE → INGEST → INDEX → RETRIEVE → GENERATE → EVALUATE**. If evaluation metrics fall below thresholds, iterate on chunking or embedding before tuning generation.

### Phase 1: CONFIGURE -- Semantic Kernel Setup

Set up Semantic Kernel with the chosen LLM provider, embedding model, and vector store. The flow: User Query → Query Embedding → Vector Search → Relevant Chunks → LLM Generation → Response.

See `references/rag-service-impl.md` for complete NuGet package references, Program.cs DI setup (Azure OpenAI and Ollama), appsettings.json, and air-gapped Ollama configuration.

### Phase 2: INGEST -- Document Processing and Chunking

Load documents, validate content extraction, and split into semantically coherent chunks. The `ChunkText` method uses sentence boundaries with configurable overlap. Spot-check 5-10 chunks before embedding — verify they are self-contained and not mid-sentence splits. For corpora > 100 documents, add hash-based change detection — see [Production Ingestion Hardening](references/production-ingestion.md).

See `references/rag-service-impl.md` for the `IngestDocumentAsync` and `ChunkText` implementations.

### Phase 3: INDEX -- Embedding and Vector Store

Embeddings are generated automatically by Semantic Kernel's `ISemanticTextMemory` during `SaveInformationAsync`. The vector store connector handles index creation and upsert. See `references/vector-store-options.md` for Azure AI Search, Qdrant, ChromaDB, and pgvector setup.

### Phase 4: RETRIEVE -- Query Processing and Ranking

Process user queries through embedding, similarity search with `MinRelevanceScore` threshold, and context assembly. The `SearchAsync` method returns ranked results by relevance. For exact-match queries, configure hybrid search.

### Phase 5: GENERATE -- Augmented Generation

The system prompt must constrain generation to provided context. Include explicit citation instructions. See `references/rag-service-impl.md` for the `RagService` implementation including `AskAsync`, `BuildContext`, and `GenerateResponseAsync`.

### Phase 6: EVALUATE -- Relevance and Accuracy

Before deploying, test retrieval quality with representative queries. Verify precision@k ≥ 0.70 and average relevance ≥ 0.75. Include adversarial queries to verify the pipeline says "I don't know" rather than hallucinating.

## Federal Compliance

For federal deployments, wrap the base `RagService` with classification validation and audit logging:
- **Data Classification**: Validate documents before ingestion (Unclassified, CUI, Classified)
- **CUI Handling**: Separate collections, CUI markings on responses
- **Audit Logging**: Who, what, when, where for every query and response
- **FedRAMP Services**: Use Azure Government endpoints (`.azure.us`) with authorized services
- **NIST AI RMF**: Governance, risk assessment, performance monitoring, transparency

See `references/rag-service-impl.md` for `FederalRagService` wrapper and `references/federal-ai-compliance.md` for full patterns.

## API Endpoints

Expose the RAG service via three endpoints: `POST /api/rag/ask` (question answering), `POST /api/rag/ingest` (document ingestion), `POST /api/rag/search` (similarity search). All require authorization. See `references/rag-service-impl.md` for complete endpoint and record type implementations.

## State Block

```
<rag-dotnet-state>
mode: [CONFIGURE | INGEST | INDEX | RETRIEVE | EVALUATE]
vector_store: [azure-ai-search | qdrant | chromadb | pgvector | none]
embedding_model: [text-embedding-3-small | nomic-embed-text | mxbai-embed-large | none]
generation_model: [gpt-4 | llama3 | none]
documents_ingested: [count or none]
index_built: [true | false]
retrieval_tested: [true | false]
federal_compliant: [true | false | n/a]
last_action: [what was just done]
next_action: [what should happen next]
</rag-dotnet-state>
```

**Example:**
```
<rag-dotnet-state>
mode: RETRIEVE
vector_store: azure-ai-search
embedding_model: text-embedding-3-small
generation_model: gpt-4
documents_ingested: 150
index_built: true
retrieval_tested: false
federal_compliant: true
last_action: Completed document ingestion for policies collection
next_action: Run retrieval evaluation with 10 representative queries
</rag-dotnet-state>
```

## Output Templates

```markdown
## RAG Implementation: [Project Name]
**Vector Store**: [store] | **LLM**: [model] | **Embedding**: [model] | **Chunk**: [size/overlap]

| Endpoint | Description |
|----------|-------------|
| POST /api/rag/ask | Question answering with citations |
| POST /api/rag/ingest | Document ingestion |
| POST /api/rag/search | Similarity search |

**Retrieval Evaluation** | Precision@5: [X.XX] (≥0.70) | Avg Relevance: [X.XX] (≥0.75) | Zero-result queries: [N]
```

## AI Discipline Rules

**Always test retrieval before tuning generation.** Run `SearchAsync` with 10+ representative queries. Inspect relevance scores — are they above `MinRelevanceScore`? Spot-check 3-5 retrieved chunks manually — are they actually relevant? Only after retrieval is solid should you tune generation prompts or switch LLMs.

**Never skip chunking validation.** One chunk size does not fit all document types. PDFs, Markdown, and code require different strategies. Before embedding, inspect 5-10 chunks from different document types: verify they are self-contained, not mid-sentence splits, and fit within the embedding model context window.

**Always include citation in generated responses.** The system prompt must instruct the LLM to cite source chunks. Uncited responses cannot be verified and are a compliance failure in federal contexts. Include document ID, chunk description, and relevance score in every response.

**Validate vector store connection before batch ingestion.** A failed connection mid-batch leaves the index in a partial state. Write and remove a health-check record before starting batch ingestion. Abort on any connection failure — partial indexes cause silent retrieval failures.

**Use FIPS-compliant models for federal deployments.** Azure Government endpoints (`.azure.us`), verify FedRAMP authorization of all services, enable FIPS mode on host OS for air-gapped Ollama deployments, and document FIPS compliance status in the deployment checklist.

## Anti-Patterns Table

| Anti-Pattern | Why It Fails | Correct Approach |
|-------------|-------------|------------------|
| **Using the generation model for embedding** | Chat models produce different vector spaces; retrieval quality collapses | Use a dedicated embedding model (text-embedding-3-small, nomic-embed-text) |
| **Single chunk size for all document types** | PDFs, Markdown, code have different structural boundaries | Use document-type-specific chunking; inspect chunks before embedding |
| **No retrieval evaluation** | Tuning prompts on bad retrieval is wasted effort | Evaluate precision@k and relevance with representative queries before touching generation |
| **Ignoring context window limits** | Stuffing too many chunks dilutes relevant information and may exceed token limits | Calculate token budget: prompt + context + expected response must fit within model context |
| **Storing PII/CUI without classification** | Federal compliance violation; data spillage risk | Validate data classification before ingestion; separate CUI into dedicated collections |
| **Treating RAG as magic search** | RAG grounds generation — it is not keyword search | Set user expectations; implement hybrid search for keyword needs |
| **Hardcoding embedding model without benchmarking** | Different models have different strengths on different domains | Benchmark 2-3 embedding models on domain-specific queries before committing |
| **No citation or source attribution** | Users cannot verify answers; compliance failure in federal contexts | Include source document ID, chunk description, and relevance score in every response |
| **Batch ingestion without connection validation** | Partial index state on connection failure; silent data loss | Test vector store connection before starting; implement retry with idempotent IDs |
| **Using MinRelevanceScore of 0.0** | Returns every chunk regardless of relevance, flooding the LLM context with noise | Set MinRelevanceScore to 0.7+ and tune based on evaluation results |
| **Splitting tables mid-row** | Rows without headers (or headers without rows) are semantically useless — retrieval returns corrupt context | Detect Markdown and HTML tables before chunking; treat as atomic units |

## Error Recovery

### Poor Retrieval Quality (precision@k < 0.50)
1. Inspect retrieved chunks manually for 3-5 queries
2. Check if chunks are too large (exceeding embedding context) or too small (losing coherence)
3. Try a different embedding model (`ada-002` → `text-embedding-3-small`, or `MiniLM` → `nomic`)
4. For exact-match queries (error codes, IDs), add hybrid search (BM25 + vector)
5. Increase TopK + add re-ranking; re-evaluate after each single change

### Embedding Model Mismatch
Verify dimension match (text-embedding-3-small: 1536, nomic: 768, mxbai: 1024). If you changed models, rebuild the entire index — drop, recreate, re-embed. Never mix embeddings from different models in the same collection.

### Vector Store Connection Failures
Check network and credentials. Azure AI Search: verify service running and index exists. Qdrant: `docker ps`, `docker logs qdrant`. pgvector: verify PostgreSQL running and extension installed. Implement circuit breaker; return graceful "service unavailable."

### Air-Gapped Deployment Issues
Verify Ollama: `curl http://localhost:11434/api/tags`. Confirm model pulled (`ollama list`) and VRAM available (~1-2GB for embeddings). For poor quality: `nomic-embed-text` → `mxbai-embed-large`. Verify local vector store accessible. Test full pipeline end-to-end before deploying to disconnected network.

## Integration with Other Skills

- **`rag-pipeline-python`** — Python counterpart using LangChain and Ollama. Core RAG principles are identical across both skills.
- **`ollama-model-workflow`** — Select, pull, and benchmark local models for air-gapped RAG deployments. Benchmark `nomic-embed-text` vs `mxbai-embed-large` on domain corpus. Match `num_ctx` to expected retrieval context size plus prompt overhead.
- **`dotnet-security-review`** + **`security-review-federal`** — Security review for federal RAG code: run the .NET base review, then the shared federal overlay (NIST SP 800-53 AC/AU controls, FIPS 140-2/3 compliance, CUI validation).
- **`mcp-server-scaffold`** — Expose the RAG pipeline as MCP tools (`search_knowledge_base`, `ask_knowledge_base`) for other AI agents to invoke.

## References

- `references/rag-service-impl.md` — Complete C# implementation (NuGet packages, Program.cs, RagService, API endpoints, federal wrapper)
- `references/federal-ai-compliance.md` — Federal compliance requirements (NIST AI RMF, FedRAMP, CUI, audit logging)
- `references/vector-store-options.md` — Vector store comparison (Azure AI Search, Qdrant, ChromaDB, pgvector)
- `references/embedding-models.md` — Embedding model options and performance characteristics
- `references/production-ingestion.md` — Incremental ingestion, chunk lifecycle, memory-bounded batching, crash resilience, heading context, table atomicity, quality gates, sidecar pattern
