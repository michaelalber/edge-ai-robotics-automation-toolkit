# Vector Store Options for .NET RAG Pipelines

## Overview

Vector stores are the backbone of any RAG system. The choice of vector store affects retrieval latency, scalability, operational complexity, and federal compliance posture. This reference covers the primary options available through Microsoft Semantic Kernel connectors.

## Comparison Table

| Feature | Azure AI Search | Qdrant | ChromaDB | PostgreSQL pgvector |
|---------|----------------|--------|----------|---------------------|
| **Managed Service** | Yes (Azure) | Self-hosted or Cloud | Self-hosted | Self-hosted or managed |
| **FedRAMP Authorized** | Yes (High) | No | No | Yes (via Azure/AWS) |
| **Max Dimensions** | 3072 | 65536 | Unlimited | 2000 |
| **Distance Metrics** | Cosine, Euclidean, DotProduct | Cosine, Euclidean, DotProduct, Manhattan | Cosine, L2, IP | Cosine, L2, IP |
| **Filtering** | OData filters, facets | Payload filtering | Metadata filtering | SQL WHERE clauses |
| **Hybrid Search** | Yes (BM25 + vector) | Yes (sparse + dense) | No | Yes (with tsvector) |
| **Semantic Kernel Connector** | Stable | Alpha | Community | Alpha |
| **Scaling** | Automatic (Azure) | Manual sharding | Single-node | Connection pooling |
| **Approximate Nearest Neighbor** | HNSW | HNSW | HNSW | HNSW (ivfflat also) |
| **Air-Gapped Deployment** | No (cloud only) | Yes (Docker/binary) | Yes (embedded/Docker) | Yes (on-premise) |
| **Backup/Recovery** | Azure-managed | Snapshot API | File copy | pg_dump / WAL |
| **Typical Latency (p50)** | 10-50ms | 5-20ms | 10-30ms | 15-50ms |
| **Production Readiness** | High | High | Medium | High |

## Azure AI Search

Best for: Azure-native deployments, federal/FedRAMP environments, hybrid search requirements.

### Configuration

```csharp
using Microsoft.SemanticKernel.Connectors.AzureAISearch;

var memoryBuilder = new MemoryBuilder()
    .WithAzureAISearchMemoryStore(
        endpoint: configuration["AzureSearch:Endpoint"]!,
        apiKey: configuration["AzureSearch:ApiKey"]!)
    .WithTextEmbeddingGeneration(embeddingService);
```

### Government Cloud

```csharp
// Azure Government endpoint pattern
var endpoint = "https://your-search.search.windows.us"; // .windows.us for Gov
```

### Strengths
- Native hybrid search (BM25 keyword + vector similarity in a single query)
- Built-in semantic ranking for re-ranking results
- FedRAMP High authorized in Azure Government regions
- Automatic index management and scaling
- Rich filtering with OData expressions

### Limitations
- Cloud-only -- cannot be deployed in air-gapped environments
- Cost scales with index size and query volume
- Semantic Kernel connector is alpha for some features
- Vendor lock-in to Azure ecosystem

### When to Choose
- Your deployment target is Azure (especially Azure Government)
- You need hybrid search (keyword + semantic)
- FedRAMP compliance is required
- You want managed infrastructure

## Qdrant

Best for: High-performance self-hosted deployments, air-gapped environments, advanced filtering.

### Configuration

```csharp
using Microsoft.SemanticKernel.Connectors.Qdrant;

var memoryBuilder = new MemoryBuilder()
    .WithQdrantMemoryStore(
        host: "http://localhost:6333",
        vectorSize: 1536) // Must match embedding model dimensions
    .WithTextEmbeddingGeneration(embeddingService);
```

### Docker Deployment

```yaml
# docker-compose.yml
services:
  qdrant:
    image: qdrant/qdrant:latest
    ports:
      - "6333:6333"  # REST API
      - "6334:6334"  # gRPC
    volumes:
      - qdrant_storage:/qdrant/storage
    environment:
      - QDRANT__SERVICE__GRPC_PORT=6334
volumes:
  qdrant_storage:
```

### Strengths
- Excellent query performance (Rust-based engine)
- Rich payload filtering with complex conditions
- Supports both REST and gRPC APIs
- Snapshot API for backup and restore
- Can run fully air-gapped via Docker or binary
- Supports multi-tenancy via collection isolation

### Limitations
- Self-hosted requires operational overhead
- No native hybrid search (must implement separately)
- Semantic Kernel connector is alpha
- Scaling requires manual shard configuration

### When to Choose
- You need air-gapped deployment capability
- Performance is a top priority
- You need advanced payload-based filtering
- You want self-hosted with low operational complexity

## ChromaDB

Best for: Development and prototyping, small-scale deployments, embedded use cases.

### Configuration

```csharp
// ChromaDB does not have an official Semantic Kernel connector.
// Use the community connector or REST API wrapper.
using System.Net.Http.Json;

public class ChromaMemoryStore : IMemoryStore
{
    private readonly HttpClient _http;

    public ChromaMemoryStore(string endpoint = "http://localhost:8000")
    {
        _http = new HttpClient { BaseAddress = new Uri(endpoint) };
    }

    // Implement IMemoryStore methods using ChromaDB REST API
}
```

### Docker Deployment

```yaml
services:
  chromadb:
    image: chromadb/chroma:latest
    ports:
      - "8000:8000"
    volumes:
      - chroma_data:/chroma/chroma
volumes:
  chroma_data:
```

### Strengths
- Simple setup for development and prototyping
- Embedded mode (in-process) for testing
- Good documentation and Python ecosystem
- Air-gapped capable via Docker

### Limitations
- No official Semantic Kernel connector (community only)
- Single-node architecture limits scalability
- Not recommended for production workloads over 1M vectors
- Limited filtering capabilities compared to Qdrant or Azure AI Search
- No hybrid search support

### When to Choose
- You are prototyping or in early development
- Your corpus is small (under 100K documents)
- You need an embedded vector store for testing
- You plan to migrate to a production store later

## PostgreSQL with pgvector

Best for: Teams already using PostgreSQL, reducing infrastructure complexity, SQL-familiar environments.

### Configuration

```csharp
using Microsoft.SemanticKernel.Connectors.Postgres;

var memoryBuilder = new MemoryBuilder()
    .WithPostgresMemoryStore(
        connectionString: configuration.GetConnectionString("VectorDb")!,
        vectorSize: 1536,
        schema: "embeddings")
    .WithTextEmbeddingGeneration(embeddingService);
```

### Schema Setup

```sql
-- Enable the pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- Example table structure (Semantic Kernel manages this)
CREATE TABLE IF NOT EXISTS embeddings.memory (
    id TEXT PRIMARY KEY,
    collection TEXT NOT NULL,
    content TEXT NOT NULL,
    metadata JSONB,
    embedding vector(1536),  -- Dimension must match embedding model
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create HNSW index for fast similarity search
CREATE INDEX ON embeddings.memory
    USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64);
```

### Strengths
- Leverages existing PostgreSQL infrastructure and expertise
- Full SQL filtering combined with vector similarity
- Hybrid search via tsvector + pgvector in a single query
- Mature backup, replication, and HA patterns (pg_dump, WAL, Patroni)
- Available in FedRAMP-authorized managed services (Azure Database for PostgreSQL, AWS RDS)
- Air-gapped deployment with on-premise PostgreSQL

### Limitations
- Performance degrades above 5-10M vectors without careful tuning
- HNSW index build time can be significant for large datasets
- Maximum 2000 dimensions (sufficient for most models)
- Requires PostgreSQL 15+ with pgvector extension
- Semantic Kernel connector is alpha

### When to Choose
- You already run PostgreSQL in your infrastructure
- You want to minimize the number of services to operate
- You need SQL-based filtering combined with vector search
- FedRAMP compliance is needed and you use a managed PostgreSQL service

## Decision Matrix

```
What is the deployment environment?
|
+-- Azure Cloud (commercial or government)?
|   --> Azure AI Search (managed, FedRAMP, hybrid search)
|
+-- Air-gapped / disconnected?
|   |
|   +-- Already running PostgreSQL?
|   |   --> pgvector (minimize new infrastructure)
|   |
|   +-- Need maximum query performance?
|   |   --> Qdrant (Rust engine, Docker deployment)
|   |
|   +-- Prototyping only?
|       --> ChromaDB (simple setup, plan to migrate)
|
+-- On-premise with cloud access?
|   |
|   +-- Want managed vector DB?
|   |   --> Qdrant Cloud or Azure AI Search
|   |
|   +-- Want self-hosted?
|       --> Qdrant or pgvector
|
+-- Development / prototyping?
    --> ChromaDB (embedded) or Qdrant (Docker)
```

## Dimension Reference

When configuring the vector store, the `vectorSize` parameter must match the embedding model's output dimensions exactly.

| Embedding Model | Dimensions | Notes |
|----------------|-----------|-------|
| text-embedding-ada-002 | 1536 | Azure OpenAI legacy |
| text-embedding-3-small | 1536 | Azure OpenAI current |
| text-embedding-3-large | 3072 | Azure OpenAI high-quality |
| nomic-embed-text (Ollama) | 768 | Local, air-gapped |
| mxbai-embed-large (Ollama) | 1024 | Local, higher quality |
| all-MiniLM-L6-v2 | 384 | sentence-transformers |
| all-mpnet-base-v2 | 768 | sentence-transformers |

See also: `embedding-models.md` for detailed embedding model comparison.
