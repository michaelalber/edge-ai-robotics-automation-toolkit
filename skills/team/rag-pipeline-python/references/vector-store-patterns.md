# Vector Store Patterns for RAG Pipelines

## Overview

Vector stores are the persistence and retrieval layer of a RAG pipeline. They store embedding vectors alongside metadata and provide efficient similarity search. The choice of vector store affects performance, scalability, deployment complexity, and feature set.

**Selection Criteria:**
- **Development/prototyping** -- ChromaDB (simplest setup, good defaults)
- **High-performance local** -- FAISS (fastest similarity search, no server needed)
- **Production with features** -- Qdrant (filtering, replication, cloud option)
- **Existing PostgreSQL stack** -- pgvector (no new infrastructure, SQL familiar)

## Performance Comparison

| Feature | ChromaDB | FAISS | Qdrant | pgvector |
|---------|----------|-------|--------|----------|
| **Setup Complexity** | Very Low | Low | Medium | Medium |
| **Server Required** | No (embedded) | No (in-process) | Yes (or embedded) | Yes (PostgreSQL) |
| **Persistence** | SQLite + Parquet | Manual save/load | Built-in | PostgreSQL |
| **Metadata Filtering** | Yes (WHERE clause) | No (manual post-filter) | Yes (rich filtering) | Yes (SQL WHERE) |
| **Max Vectors (practical)** | ~1M | ~100M+ | ~100M+ | ~10M |
| **Query Latency (1M vectors)** | ~10-50ms | ~1-5ms | ~5-20ms | ~20-100ms |
| **Hybrid Search** | No | No | Yes (sparse + dense) | Yes (tsvector + ivfflat) |
| **Cloud Hosted Option** | No | No | Yes (Qdrant Cloud) | Yes (any managed PG) |
| **Python Client** | chromadb | faiss-cpu/faiss-gpu | qdrant-client | psycopg2 + pgvector |
| **LangChain Integration** | langchain-chroma | langchain-community | langchain-qdrant | langchain-postgres |
| **Best For** | Prototyping, small corpora | Large-scale, low-latency | Production, rich features | Existing PG infrastructure |

---

## ChromaDB (Primary Recommendation)

ChromaDB is an open-source embedding database designed for AI applications. It runs embedded (no server) or as a client-server, with automatic persistence and built-in metadata filtering.

### Installation

```bash
pip install chromadb langchain-chroma
```

### Basic Setup

```python
import chromadb
from langchain_chroma import Chroma
from langchain_community.embeddings import HuggingFaceEmbeddings


def create_chroma_vectorstore(
    documents: list,
    embedding_model: str = "all-MiniLM-L6-v2",
    persist_directory: str = "./chroma_db",
    collection_name: str = "rag_collection",
) -> Chroma:
    """Create and populate a ChromaDB vector store.

    Args:
        documents: List of LangChain Document objects (chunked).
        embedding_model: HuggingFace model name for embeddings.
        persist_directory: Directory to persist the database.
        collection_name: Name of the collection.

    Returns:
        Chroma vector store instance.
    """
    embeddings = HuggingFaceEmbeddings(
        model_name=embedding_model,
        encode_kwargs={"normalize_embeddings": True},
    )

    vectorstore = Chroma.from_documents(
        documents=documents,
        embedding=embeddings,
        persist_directory=persist_directory,
        collection_name=collection_name,
    )
    print(f"ChromaDB: Indexed {len(documents)} documents in '{collection_name}'")
    return vectorstore


def load_chroma_vectorstore(
    embedding_model: str = "all-MiniLM-L6-v2",
    persist_directory: str = "./chroma_db",
    collection_name: str = "rag_collection",
) -> Chroma:
    """Load an existing ChromaDB vector store from disk.

    Args:
        embedding_model: Must match the model used during indexing.
        persist_directory: Directory where the database is persisted.
        collection_name: Name of the collection to load.

    Returns:
        Chroma vector store instance.
    """
    embeddings = HuggingFaceEmbeddings(
        model_name=embedding_model,
        encode_kwargs={"normalize_embeddings": True},
    )

    vectorstore = Chroma(
        persist_directory=persist_directory,
        embedding_function=embeddings,
        collection_name=collection_name,
    )
    print(f"ChromaDB: Loaded collection '{collection_name}' from {persist_directory}")
    return vectorstore
```

### CRUD Operations

```python
from langchain_core.documents import Document


def add_documents_to_chroma(vectorstore: Chroma, documents: list) -> list[str]:
    """Add new documents to an existing ChromaDB collection.

    Args:
        vectorstore: Existing Chroma vector store.
        documents: List of LangChain Document objects to add.

    Returns:
        List of document IDs assigned by ChromaDB.
    """
    ids = vectorstore.add_documents(documents)
    print(f"ChromaDB: Added {len(documents)} documents")
    return ids


def delete_documents_from_chroma(vectorstore: Chroma, ids: list[str]) -> None:
    """Delete documents from ChromaDB by their IDs.

    Args:
        vectorstore: Existing Chroma vector store.
        ids: List of document IDs to delete.
    """
    vectorstore.delete(ids=ids)
    print(f"ChromaDB: Deleted {len(ids)} documents")


def search_chroma(
    vectorstore: Chroma,
    query: str,
    top_k: int = 5,
    filter_dict: dict = None,
) -> list:
    """Search ChromaDB with optional metadata filtering.

    Args:
        vectorstore: Chroma vector store.
        query: Search query string.
        top_k: Number of results to return.
        filter_dict: Optional metadata filter (ChromaDB WHERE clause).
            Example: {"source": "docs/api.md"}
            Example: {"page_number": {"$gte": 5}}

    Returns:
        List of (Document, score) tuples.
    """
    search_kwargs = {"k": top_k}
    if filter_dict:
        search_kwargs["filter"] = filter_dict

    results = vectorstore.similarity_search_with_relevance_scores(
        query,
        **search_kwargs,
    )
    for doc, score in results:
        source = doc.metadata.get("source", "unknown")
        print(f"  [{score:.3f}] {source}: {doc.page_content[:80]}...")
    return results
```

### Metadata Filtering Examples

```python
# Filter by source document
results = search_chroma(
    vectorstore, "database configuration",
    filter_dict={"source": "docs/database.md"},
)

# Filter by page number range (PDF)
results = search_chroma(
    vectorstore, "authentication",
    filter_dict={"page_number": {"$gte": 10, "$lte": 20}},
)

# Filter by document type
results = search_chroma(
    vectorstore, "function signature",
    filter_dict={"doc_type": "code"},
)

# Combine filters with $and
results = search_chroma(
    vectorstore, "error handling",
    filter_dict={
        "$and": [
            {"doc_type": "code"},
            {"language": "python"},
        ]
    },
)
```

### Collection Management

```python
import chromadb


def list_collections(persist_directory: str = "./chroma_db") -> list[str]:
    """List all collections in a ChromaDB instance."""
    client = chromadb.PersistentClient(path=persist_directory)
    collections = client.list_collections()
    for col in collections:
        count = col.count()
        print(f"  {col.name}: {count} documents")
    return [col.name for col in collections]


def delete_collection(
    collection_name: str,
    persist_directory: str = "./chroma_db",
) -> None:
    """Delete an entire collection from ChromaDB."""
    client = chromadb.PersistentClient(path=persist_directory)
    client.delete_collection(collection_name)
    print(f"ChromaDB: Deleted collection '{collection_name}'")


def get_collection_stats(
    collection_name: str,
    persist_directory: str = "./chroma_db",
) -> dict:
    """Get statistics about a ChromaDB collection."""
    client = chromadb.PersistentClient(path=persist_directory)
    collection = client.get_collection(collection_name)

    count = collection.count()
    peek = collection.peek(limit=3)

    stats = {
        "name": collection_name,
        "document_count": count,
        "sample_metadata": peek.get("metadatas", [])[:3],
    }
    print(f"Collection '{collection_name}': {count} documents")
    return stats
```

---

## FAISS (Facebook AI Similarity Search)

FAISS is optimized for billion-scale similarity search. It runs in-process (no server), is extremely fast, but lacks built-in persistence and metadata filtering.

### Installation

```bash
# CPU version
pip install faiss-cpu langchain-community

# GPU version (requires CUDA)
pip install faiss-gpu langchain-community
```

### Basic Setup

```python
from langchain_community.vectorstores import FAISS
from langchain_community.embeddings import HuggingFaceEmbeddings


def create_faiss_vectorstore(
    documents: list,
    embedding_model: str = "all-MiniLM-L6-v2",
    save_path: str = "./faiss_index",
) -> FAISS:
    """Create a FAISS vector store and save to disk.

    Args:
        documents: List of LangChain Document objects (chunked).
        embedding_model: HuggingFace model name.
        save_path: Directory to save the FAISS index.

    Returns:
        FAISS vector store instance.
    """
    embeddings = HuggingFaceEmbeddings(
        model_name=embedding_model,
        encode_kwargs={"normalize_embeddings": True},
    )

    vectorstore = FAISS.from_documents(documents, embeddings)
    vectorstore.save_local(save_path)
    print(f"FAISS: Indexed {len(documents)} documents, saved to {save_path}")
    return vectorstore


def load_faiss_vectorstore(
    embedding_model: str = "all-MiniLM-L6-v2",
    save_path: str = "./faiss_index",
) -> FAISS:
    """Load an existing FAISS index from disk.

    Args:
        embedding_model: Must match the model used during indexing.
        save_path: Directory containing the saved FAISS index.

    Returns:
        FAISS vector store instance.
    """
    embeddings = HuggingFaceEmbeddings(
        model_name=embedding_model,
        encode_kwargs={"normalize_embeddings": True},
    )

    vectorstore = FAISS.load_local(
        save_path,
        embeddings,
        allow_dangerous_deserialization=True,
    )
    print(f"FAISS: Loaded index from {save_path}")
    return vectorstore
```

### CRUD Operations

```python
def add_documents_to_faiss(
    vectorstore: FAISS,
    documents: list,
    save_path: str = "./faiss_index",
) -> list[str]:
    """Add documents to FAISS and persist the updated index.

    FAISS does not auto-persist -- you must save after modifications.
    """
    ids = vectorstore.add_documents(documents)
    vectorstore.save_local(save_path)
    print(f"FAISS: Added {len(documents)} documents, saved to {save_path}")
    return ids


def search_faiss(
    vectorstore: FAISS,
    query: str,
    top_k: int = 5,
) -> list:
    """Search FAISS for similar documents.

    Note: FAISS does not support metadata filtering natively.
    For filtered search, retrieve more results and filter in Python.
    """
    results = vectorstore.similarity_search_with_score(query, k=top_k)
    for doc, score in results:
        source = doc.metadata.get("source", "unknown")
        print(f"  [{score:.3f}] {source}: {doc.page_content[:80]}...")
    return results


def search_faiss_with_filter(
    vectorstore: FAISS,
    query: str,
    filter_key: str,
    filter_value: str,
    top_k: int = 5,
    fetch_k: int = 50,
) -> list:
    """Search FAISS with post-hoc metadata filtering.

    Fetches more results than needed, then filters by metadata.

    Args:
        vectorstore: FAISS vector store.
        query: Search query.
        filter_key: Metadata key to filter on.
        filter_value: Required value for the filter key.
        top_k: Number of filtered results to return.
        fetch_k: Number of results to fetch before filtering.
    """
    # Fetch extra results to filter from
    results = vectorstore.similarity_search_with_score(query, k=fetch_k)

    # Filter by metadata
    filtered = [
        (doc, score) for doc, score in results
        if doc.metadata.get(filter_key) == filter_value
    ]

    return filtered[:top_k]
```

### FAISS Index Types

```python
import faiss
import numpy as np


def create_optimized_faiss_index(
    dimension: int,
    num_vectors: int,
) -> faiss.Index:
    """Create an optimized FAISS index based on dataset size.

    Args:
        dimension: Embedding vector dimension.
        num_vectors: Expected number of vectors.

    Returns:
        Configured FAISS index.

    Selection guide:
        < 10k vectors   -> Flat (exact search)
        10k - 1M        -> IVF with Flat quantizer
        1M - 100M       -> IVF with PQ (Product Quantization)
        > 100M          -> IVFPQ with OPQ preprocessing
    """
    if num_vectors < 10_000:
        # Exact search, best quality, O(n) per query
        index = faiss.IndexFlatIP(dimension)
        print(f"FAISS: Using Flat index (exact search) for {num_vectors} vectors")

    elif num_vectors < 1_000_000:
        # Inverted file index with flat quantizer
        nlist = min(int(num_vectors ** 0.5), 4096)
        quantizer = faiss.IndexFlatIP(dimension)
        index = faiss.IndexIVFFlat(quantizer, dimension, nlist)
        print(f"FAISS: Using IVFFlat index (nlist={nlist}) for {num_vectors} vectors")

    else:
        # Product quantization for memory efficiency
        nlist = min(int(num_vectors ** 0.5), 65536)
        m = 16  # Number of sub-quantizers
        nbits = 8  # Bits per sub-quantizer
        quantizer = faiss.IndexFlatIP(dimension)
        index = faiss.IndexIVFPQ(quantizer, dimension, nlist, m, nbits)
        print(f"FAISS: Using IVFPQ index (nlist={nlist}, m={m}) for {num_vectors} vectors")

    return index
```

---

## Qdrant

Qdrant is a vector similarity search engine with rich filtering, payload storage, and production-ready features (replication, sharding, snapshots).

### Installation

```bash
# Client library
pip install qdrant-client langchain-qdrant

# Run Qdrant server locally (Docker)
# docker run -p 6333:6333 qdrant/qdrant
```

### Basic Setup

```python
from qdrant_client import QdrantClient
from langchain_qdrant import QdrantVectorStore
from langchain_community.embeddings import HuggingFaceEmbeddings


def create_qdrant_vectorstore(
    documents: list,
    embedding_model: str = "all-MiniLM-L6-v2",
    collection_name: str = "rag_collection",
    url: str = "http://localhost:6333",
    use_memory: bool = False,
) -> QdrantVectorStore:
    """Create a Qdrant vector store.

    Args:
        documents: List of LangChain Document objects (chunked).
        embedding_model: HuggingFace model name.
        collection_name: Qdrant collection name.
        url: Qdrant server URL (ignored if use_memory=True).
        use_memory: If True, use in-memory storage (no server needed).

    Returns:
        QdrantVectorStore instance.
    """
    embeddings = HuggingFaceEmbeddings(
        model_name=embedding_model,
        encode_kwargs={"normalize_embeddings": True},
    )

    if use_memory:
        # In-memory mode -- no server required, data lost on exit
        vectorstore = QdrantVectorStore.from_documents(
            documents=documents,
            embedding=embeddings,
            collection_name=collection_name,
            location=":memory:",
        )
    else:
        # Server mode -- connects to running Qdrant instance
        vectorstore = QdrantVectorStore.from_documents(
            documents=documents,
            embedding=embeddings,
            collection_name=collection_name,
            url=url,
        )

    print(f"Qdrant: Indexed {len(documents)} documents in '{collection_name}'")
    return vectorstore


def load_qdrant_vectorstore(
    embedding_model: str = "all-MiniLM-L6-v2",
    collection_name: str = "rag_collection",
    url: str = "http://localhost:6333",
) -> QdrantVectorStore:
    """Connect to an existing Qdrant collection."""
    embeddings = HuggingFaceEmbeddings(
        model_name=embedding_model,
        encode_kwargs={"normalize_embeddings": True},
    )

    vectorstore = QdrantVectorStore.from_existing_collection(
        embedding=embeddings,
        collection_name=collection_name,
        url=url,
    )
    print(f"Qdrant: Connected to collection '{collection_name}'")
    return vectorstore
```

### CRUD Operations

```python
from qdrant_client.models import Filter, FieldCondition, MatchValue, Range


def search_qdrant(
    vectorstore: QdrantVectorStore,
    query: str,
    top_k: int = 5,
    source_filter: str = None,
) -> list:
    """Search Qdrant with optional metadata filtering.

    Args:
        vectorstore: QdrantVectorStore instance.
        query: Search query string.
        top_k: Number of results.
        source_filter: Optional source document to filter by.
    """
    search_kwargs = {"k": top_k}

    if source_filter:
        search_kwargs["filter"] = Filter(
            must=[
                FieldCondition(
                    key="metadata.source",
                    match=MatchValue(value=source_filter),
                )
            ]
        )

    results = vectorstore.similarity_search_with_score(query, **search_kwargs)
    for doc, score in results:
        source = doc.metadata.get("source", "unknown")
        print(f"  [{score:.3f}] {source}: {doc.page_content[:80]}...")
    return results


def add_documents_to_qdrant(vectorstore: QdrantVectorStore, documents: list) -> list[str]:
    """Add documents to an existing Qdrant collection."""
    ids = vectorstore.add_documents(documents)
    print(f"Qdrant: Added {len(documents)} documents")
    return ids
```

### Advanced Filtering

```python
from qdrant_client.models import Filter, FieldCondition, MatchValue, Range


def search_qdrant_advanced(
    client: QdrantClient,
    collection_name: str,
    query_vector: list[float],
    top_k: int = 5,
) -> list:
    """Demonstrate advanced Qdrant filtering capabilities.

    Uses the native client for full control over filtering.
    """
    # Filter by exact match
    filter_by_source = Filter(
        must=[
            FieldCondition(
                key="source",
                match=MatchValue(value="docs/api.md"),
            )
        ]
    )

    # Filter by numeric range
    filter_by_page = Filter(
        must=[
            FieldCondition(
                key="page_number",
                range=Range(gte=5, lte=20),
            )
        ]
    )

    # Combine filters (AND)
    combined_filter = Filter(
        must=[
            FieldCondition(key="doc_type", match=MatchValue(value="code")),
            FieldCondition(key="language", match=MatchValue(value="python")),
        ]
    )

    # Exclude certain sources (NOT)
    exclude_filter = Filter(
        must_not=[
            FieldCondition(key="source", match=MatchValue(value="deprecated.md")),
        ]
    )

    results = client.search(
        collection_name=collection_name,
        query_vector=query_vector,
        query_filter=combined_filter,
        limit=top_k,
    )
    return results
```

### Collection Management

```python
from qdrant_client import QdrantClient
from qdrant_client.models import Distance, VectorParams


def create_qdrant_collection(
    client: QdrantClient,
    collection_name: str,
    vector_size: int = 384,
    distance: Distance = Distance.COSINE,
) -> None:
    """Create a Qdrant collection with explicit configuration."""
    client.create_collection(
        collection_name=collection_name,
        vectors_config=VectorParams(
            size=vector_size,
            distance=distance,
        ),
    )
    print(f"Qdrant: Created collection '{collection_name}' (dim={vector_size})")


def get_qdrant_collection_info(
    client: QdrantClient,
    collection_name: str,
) -> dict:
    """Get information about a Qdrant collection."""
    info = client.get_collection(collection_name)
    stats = {
        "name": collection_name,
        "points_count": info.points_count,
        "vectors_count": info.vectors_count,
        "vector_size": info.config.params.vectors.size,
        "distance": info.config.params.vectors.distance.name,
        "status": info.status.name,
    }
    print(f"Qdrant collection '{collection_name}':")
    for key, value in stats.items():
        print(f"  {key}: {value}")
    return stats


def delete_qdrant_collection(
    client: QdrantClient,
    collection_name: str,
) -> None:
    """Delete a Qdrant collection."""
    client.delete_collection(collection_name)
    print(f"Qdrant: Deleted collection '{collection_name}'")
```

---

## pgvector (PostgreSQL Extension)

pgvector adds vector similarity search to PostgreSQL. Use it when you already have a PostgreSQL deployment and want to avoid adding another database to your stack.

### Installation

```bash
# Python client
pip install psycopg2-binary pgvector langchain-postgres

# PostgreSQL extension (run in psql)
# CREATE EXTENSION IF NOT EXISTS vector;
```

### Docker Setup for Development

```bash
# Start PostgreSQL with pgvector extension
docker run -d \
    --name pgvector-db \
    -e POSTGRES_USER=rag_user \
    -e POSTGRES_PASSWORD=rag_password \
    -e POSTGRES_DB=rag_db \
    -p 5432:5432 \
    pgvector/pgvector:pg16
```

### Basic Setup

```python
from langchain_postgres import PGVector
from langchain_community.embeddings import HuggingFaceEmbeddings


def create_pgvector_vectorstore(
    documents: list,
    embedding_model: str = "all-MiniLM-L6-v2",
    collection_name: str = "rag_collection",
    connection_string: str = "postgresql+psycopg://rag_user:rag_password@localhost:5432/rag_db",
) -> PGVector:
    """Create a pgvector-backed vector store.

    Args:
        documents: List of LangChain Document objects (chunked).
        embedding_model: HuggingFace model name.
        collection_name: Name for the vector collection.
        connection_string: PostgreSQL connection string.

    Returns:
        PGVector instance.
    """
    embeddings = HuggingFaceEmbeddings(
        model_name=embedding_model,
        encode_kwargs={"normalize_embeddings": True},
    )

    vectorstore = PGVector.from_documents(
        documents=documents,
        embedding=embeddings,
        collection_name=collection_name,
        connection=connection_string,
        pre_delete_collection=False,
    )
    print(f"pgvector: Indexed {len(documents)} documents in '{collection_name}'")
    return vectorstore


def load_pgvector_vectorstore(
    embedding_model: str = "all-MiniLM-L6-v2",
    collection_name: str = "rag_collection",
    connection_string: str = "postgresql+psycopg://rag_user:rag_password@localhost:5432/rag_db",
) -> PGVector:
    """Connect to an existing pgvector collection."""
    embeddings = HuggingFaceEmbeddings(
        model_name=embedding_model,
        encode_kwargs={"normalize_embeddings": True},
    )

    vectorstore = PGVector(
        embeddings=embeddings,
        collection_name=collection_name,
        connection=connection_string,
    )
    print(f"pgvector: Connected to collection '{collection_name}'")
    return vectorstore
```

### CRUD Operations

```python
def add_documents_to_pgvector(vectorstore: PGVector, documents: list) -> list[str]:
    """Add documents to an existing pgvector collection."""
    ids = vectorstore.add_documents(documents)
    print(f"pgvector: Added {len(documents)} documents")
    return ids


def search_pgvector(
    vectorstore: PGVector,
    query: str,
    top_k: int = 5,
    filter_dict: dict = None,
) -> list:
    """Search pgvector with optional metadata filtering.

    Args:
        vectorstore: PGVector instance.
        query: Search query string.
        top_k: Number of results.
        filter_dict: Metadata filter dictionary.
    """
    search_kwargs = {"k": top_k}
    if filter_dict:
        search_kwargs["filter"] = filter_dict

    results = vectorstore.similarity_search_with_score(query, **search_kwargs)
    for doc, score in results:
        source = doc.metadata.get("source", "unknown")
        print(f"  [{score:.3f}] {source}: {doc.page_content[:80]}...")
    return results
```

### Direct SQL Operations

```python
import psycopg2
from pgvector.psycopg2 import register_vector


def pgvector_direct_operations(connection_string: str) -> None:
    """Demonstrate direct SQL operations with pgvector.

    Useful for advanced queries, index management, and maintenance.
    """
    conn = psycopg2.connect(connection_string)
    register_vector(conn)
    cur = conn.cursor()

    # Create table with vector column
    cur.execute("""
        CREATE TABLE IF NOT EXISTS documents (
            id SERIAL PRIMARY KEY,
            content TEXT NOT NULL,
            source TEXT,
            doc_type TEXT,
            embedding vector(384),  -- Match your embedding dimension
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)

    # Create an IVFFlat index for approximate nearest neighbor search
    # Lists parameter: sqrt(num_rows) is a good starting point
    cur.execute("""
        CREATE INDEX IF NOT EXISTS documents_embedding_idx
        ON documents
        USING ivfflat (embedding vector_cosine_ops)
        WITH (lists = 100)
    """)

    # Insert a document with its embedding
    # embedding = model.encode("some text")  # Your embedding
    # cur.execute(
    #     "INSERT INTO documents (content, source, embedding) VALUES (%s, %s, %s)",
    #     ("document content", "source.md", embedding.tolist()),
    # )

    # Similarity search with metadata filter
    # query_embedding = model.encode("search query")
    # cur.execute(
    #     """
    #     SELECT content, source, 1 - (embedding <=> %s::vector) AS similarity
    #     FROM documents
    #     WHERE doc_type = %s
    #     ORDER BY embedding <=> %s::vector
    #     LIMIT %s
    #     """,
    #     (query_embedding.tolist(), "markdown", query_embedding.tolist(), 5),
    # )

    conn.commit()
    cur.close()
    conn.close()


def create_pgvector_hnsw_index(connection_string: str, table: str = "documents") -> None:
    """Create an HNSW index for faster queries (pgvector 0.5+).

    HNSW is faster than IVFFlat for queries but slower to build.
    Use for production workloads with frequent queries and infrequent updates.
    """
    conn = psycopg2.connect(connection_string)
    cur = conn.cursor()

    cur.execute(f"""
        CREATE INDEX IF NOT EXISTS {table}_embedding_hnsw_idx
        ON {table}
        USING hnsw (embedding vector_cosine_ops)
        WITH (m = 16, ef_construction = 64)
    """)

    conn.commit()
    cur.close()
    conn.close()
    print(f"pgvector: Created HNSW index on {table}")
```

---

## Hybrid Search (Dense + Sparse)

Hybrid search combines dense vector similarity (semantic meaning) with sparse keyword matching (exact terms) for better retrieval, especially when queries contain specific technical terms.

### Qdrant Hybrid Search

```python
from qdrant_client import QdrantClient
from qdrant_client.models import (
    Distance,
    VectorParams,
    SparseVectorParams,
    SparseIndexParams,
    NamedVector,
    NamedSparseVector,
    SparseVector,
    SearchRequest,
    FusionQuery,
    Fusion,
)


def setup_qdrant_hybrid_collection(
    client: QdrantClient,
    collection_name: str,
    dense_dim: int = 384,
) -> None:
    """Create a Qdrant collection supporting both dense and sparse vectors."""
    client.create_collection(
        collection_name=collection_name,
        vectors_config={
            "dense": VectorParams(size=dense_dim, distance=Distance.COSINE),
        },
        sparse_vectors_config={
            "sparse": SparseVectorParams(
                index=SparseIndexParams(on_disk=False),
            ),
        },
    )
    print(f"Qdrant hybrid: Created collection '{collection_name}'")
```

### BM25 + Dense Search with LangChain

```python
from langchain.retrievers import EnsembleRetriever
from langchain_community.retrievers import BM25Retriever
from langchain_chroma import Chroma


def create_hybrid_retriever(
    documents: list,
    vectorstore: Chroma,
    bm25_weight: float = 0.3,
    dense_weight: float = 0.7,
    top_k: int = 5,
) -> EnsembleRetriever:
    """Create a hybrid retriever combining BM25 and dense search.

    Args:
        documents: Original chunked documents (for BM25 indexing).
        vectorstore: Vector store with dense embeddings.
        bm25_weight: Weight for BM25 keyword results (0-1).
        dense_weight: Weight for dense vector results (0-1).
        top_k: Number of results from each retriever.

    Returns:
        EnsembleRetriever that combines both approaches.
    """
    # BM25 (sparse keyword matching)
    bm25_retriever = BM25Retriever.from_documents(documents, k=top_k)

    # Dense vector retriever
    dense_retriever = vectorstore.as_retriever(search_kwargs={"k": top_k})

    # Combine with Reciprocal Rank Fusion
    hybrid_retriever = EnsembleRetriever(
        retrievers=[bm25_retriever, dense_retriever],
        weights=[bm25_weight, dense_weight],
    )

    print(f"Hybrid retriever: BM25 weight={bm25_weight}, Dense weight={dense_weight}")
    return hybrid_retriever
```

---

## Embedding Model Selection Guide

### Local Models (sentence-transformers / Ollama)

| Model | Dimensions | Max Tokens | Size (MB) | MTEB Score | Speed | Best For |
|-------|-----------|-----------|----------|-----------|-------|----------|
| all-MiniLM-L6-v2 | 384 | 256 | 80 | 56.3 | Fast | Prototyping, CPU environments |
| all-mpnet-base-v2 | 768 | 384 | 420 | 57.8 | Medium | General-purpose, good quality |
| nomic-embed-text (Ollama) | 768 | 8192 | 274 | 62.4 | Medium | Long documents, Ollama stack |
| mxbai-embed-large (Ollama) | 1024 | 512 | 670 | 64.7 | Slow | Highest local quality |
| bge-small-en-v1.5 | 384 | 512 | 130 | 62.2 | Fast | Good balance, small footprint |
| bge-large-en-v1.5 | 1024 | 512 | 1340 | 64.2 | Slow | High quality, GPU required |

### Cloud Models

| Model | Dimensions | Max Tokens | Price (per 1M tokens) | Best For |
|-------|-----------|-----------|----------------------|----------|
| text-embedding-3-small (OpenAI) | 1536 | 8191 | $0.02 | Cost-effective cloud |
| text-embedding-3-large (OpenAI) | 3072 | 8191 | $0.13 | Highest cloud quality |
| embed-v3 (Cohere) | 1024 | 512 | $0.10 | Multilingual |
| voyage-large-2 (Voyage AI) | 1536 | 16000 | $0.12 | Long context, code |

### Choosing an Embedding Model

```
Decision flowchart:

1. Must data stay local?
   YES --> Go to step 2
   NO  --> Consider OpenAI text-embedding-3-small (best cost/quality)

2. Is a GPU available?
   YES --> all-mpnet-base-v2 or nomic-embed-text (via Ollama)
   NO  --> all-MiniLM-L6-v2 (fastest on CPU)

3. Are documents long (> 1000 tokens)?
   YES --> nomic-embed-text (8192 token context)
   NO  --> all-mpnet-base-v2 (better quality for short text)

4. Need multilingual?
   YES --> paraphrase-multilingual-MiniLM-L12-v2 (local)
          or Cohere embed-v3 (cloud)
   NO  --> Stick with English-optimized models
```

```python
from langchain_community.embeddings import HuggingFaceEmbeddings
from langchain_ollama import OllamaEmbeddings


def get_embedding_model(
    model_name: str = "all-MiniLM-L6-v2",
    provider: str = "sentence-transformers",
    device: str = "cuda",
) -> object:
    """Factory function for embedding model initialization.

    Args:
        model_name: Model identifier.
        provider: "sentence-transformers" or "ollama".
        device: "cuda" or "cpu" (sentence-transformers only).

    Returns:
        Configured embedding model instance.
    """
    if provider == "sentence-transformers":
        return HuggingFaceEmbeddings(
            model_name=model_name,
            model_kwargs={"device": device},
            encode_kwargs={"normalize_embeddings": True, "batch_size": 64},
        )
    elif provider == "ollama":
        return OllamaEmbeddings(model=model_name)
    else:
        raise ValueError(f"Unknown provider: {provider}")


# Usage examples
embeddings_fast = get_embedding_model("all-MiniLM-L6-v2", "sentence-transformers", "cpu")
embeddings_quality = get_embedding_model("all-mpnet-base-v2", "sentence-transformers", "cuda")
embeddings_ollama = get_embedding_model("nomic-embed-text", "ollama")
```

---

## Incremental Indexing

For large or frequently updated corpora, rebuild-from-scratch is expensive. Use incremental indexing to add, update, or remove documents without re-indexing everything.

```python
import hashlib
import json
from pathlib import Path
from langchain_core.documents import Document


class IncrementalIndexer:
    """Manages incremental updates to a vector store.

    Tracks document hashes to detect additions, modifications,
    and deletions without re-indexing the entire corpus.
    """

    def __init__(self, vectorstore, hash_store_path: str = "./doc_hashes.json"):
        self.vectorstore = vectorstore
        self.hash_store_path = Path(hash_store_path)
        self.doc_hashes = self._load_hashes()

    def _load_hashes(self) -> dict:
        """Load stored document hashes from disk."""
        if self.hash_store_path.exists():
            with open(self.hash_store_path, "r") as f:
                return json.load(f)
        return {}

    def _save_hashes(self) -> None:
        """Persist document hashes to disk."""
        with open(self.hash_store_path, "w") as f:
            json.dump(self.doc_hashes, f, indent=2)

    def _compute_hash(self, content: str) -> str:
        """Compute SHA-256 hash of document content."""
        return hashlib.sha256(content.encode()).hexdigest()

    def sync(self, documents: list[Document]) -> dict:
        """Synchronize vector store with current document set.

        Detects new, modified, and deleted documents and updates
        the vector store accordingly.

        Returns:
            Summary of changes made.
        """
        current_hashes = {}
        to_add = []
        to_update = []
        to_delete = []

        for doc in documents:
            source = doc.metadata.get("source", "unknown")
            content_hash = self._compute_hash(doc.page_content)
            current_hashes[source] = content_hash

            if source not in self.doc_hashes:
                to_add.append(doc)
            elif self.doc_hashes[source] != content_hash:
                to_update.append(doc)

        # Find deleted documents
        for source in self.doc_hashes:
            if source not in current_hashes:
                to_delete.append(source)

        # Apply changes
        if to_add:
            self.vectorstore.add_documents(to_add)
        if to_update:
            # Delete old versions, then add updated ones
            update_sources = [d.metadata["source"] for d in to_update]
            # Note: deletion by metadata varies by vector store
            self.vectorstore.add_documents(to_update)
        # to_delete handling depends on vector store capabilities

        # Update hash store
        self.doc_hashes = current_hashes
        self._save_hashes()

        summary = {
            "added": len(to_add),
            "updated": len(to_update),
            "deleted": len(to_delete),
            "unchanged": len(documents) - len(to_add) - len(to_update),
        }
        print(f"Incremental sync: +{summary['added']} ~{summary['updated']} -{summary['deleted']}")
        return summary
```

---

## Testing Vector Store Operations

```python
import pytest
from langchain_core.documents import Document
from langchain_community.embeddings import HuggingFaceEmbeddings
from langchain_chroma import Chroma


@pytest.fixture
def sample_documents():
    """Create sample documents for testing."""
    return [
        Document(
            page_content="Python is a programming language.",
            metadata={"source": "python.md", "doc_type": "tutorial"},
        ),
        Document(
            page_content="PostgreSQL is a relational database.",
            metadata={"source": "postgres.md", "doc_type": "reference"},
        ),
        Document(
            page_content="ChromaDB stores embedding vectors for similarity search.",
            metadata={"source": "chromadb.md", "doc_type": "reference"},
        ),
    ]


@pytest.fixture
def embeddings():
    """Create embedding model for testing."""
    return HuggingFaceEmbeddings(
        model_name="all-MiniLM-L6-v2",
        encode_kwargs={"normalize_embeddings": True},
    )


@pytest.fixture
def vectorstore(sample_documents, embeddings):
    """Create a test ChromaDB vector store."""
    store = Chroma.from_documents(
        documents=sample_documents,
        embedding=embeddings,
        collection_name="test_collection",
    )
    yield store
    store.delete_collection()


def test_similarity_search_returns_results(vectorstore):
    """Verify that similarity search returns relevant documents."""
    results = vectorstore.similarity_search("programming language", k=2)
    assert len(results) == 2
    assert any("Python" in r.page_content for r in results)


def test_similarity_search_with_scores(vectorstore):
    """Verify that similarity scores are returned and ordered."""
    results = vectorstore.similarity_search_with_relevance_scores("database", k=2)
    assert len(results) == 2
    scores = [score for _, score in results]
    assert scores == sorted(scores, reverse=True), "Results should be sorted by score descending"


def test_metadata_preserved(vectorstore):
    """Verify that document metadata is preserved after indexing."""
    results = vectorstore.similarity_search("Python", k=1)
    assert results[0].metadata["source"] == "python.md"
    assert results[0].metadata["doc_type"] == "tutorial"


def test_add_documents(vectorstore, embeddings):
    """Verify that documents can be added incrementally."""
    new_doc = Document(
        page_content="FAISS provides fast similarity search.",
        metadata={"source": "faiss.md", "doc_type": "reference"},
    )
    vectorstore.add_documents([new_doc])

    results = vectorstore.similarity_search("fast similarity", k=1)
    assert "FAISS" in results[0].page_content


def test_metadata_filter(vectorstore):
    """Verify that metadata filtering works correctly."""
    results = vectorstore.similarity_search(
        "search",
        k=5,
        filter={"doc_type": "reference"},
    )
    for doc in results:
        assert doc.metadata["doc_type"] == "reference"
```

---

## Quick Reference: Setup Commands

```bash
# Environment setup
python -m venv rag-env
source rag-env/bin/activate  # Linux/Mac
# rag-env\Scripts\activate   # Windows

# Core dependencies
pip install langchain langchain-community langchain-core
pip install sentence-transformers

# Vector stores (install the one you need)
pip install chromadb langchain-chroma                  # ChromaDB
pip install faiss-cpu                                  # FAISS (CPU)
pip install faiss-gpu                                  # FAISS (GPU)
pip install qdrant-client langchain-qdrant             # Qdrant
pip install psycopg2-binary pgvector langchain-postgres # pgvector

# Ollama integration
pip install langchain-ollama ollama

# Document processing
pip install pypdf pdfplumber unstructured

# Testing
pip install pytest pytest-asyncio

# Optional: LlamaIndex alternative
pip install llama-index llama-index-embeddings-huggingface
pip install llama-index-vector-stores-chroma
```
