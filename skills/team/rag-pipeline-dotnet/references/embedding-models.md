# Embedding Models for .NET RAG Pipelines

## Overview

The embedding model is the single most important component in a RAG pipeline. It determines the ceiling of retrieval quality -- no amount of generation tuning can compensate for poor embeddings. This reference covers the models available through Semantic Kernel connectors, with performance characteristics and selection guidance.

## Comparison Table

| Model | Provider | Dimensions | Max Tokens | Speed (docs/sec) | Quality (MTEB avg) | Cost | Air-Gapped |
|-------|----------|-----------|------------|-------------------|---------------------|------|------------|
| text-embedding-3-small | Azure OpenAI | 1536 | 8191 | ~500 | 62.3 | $0.02/1M tokens | No |
| text-embedding-3-large | Azure OpenAI | 3072 | 8191 | ~300 | 64.6 | $0.13/1M tokens | No |
| text-embedding-ada-002 | Azure OpenAI | 1536 | 8191 | ~500 | 61.0 | $0.10/1M tokens | No |
| nomic-embed-text | Ollama | 768 | 8192 | ~100-300* | 59.4 | Free (compute) | Yes |
| mxbai-embed-large | Ollama | 1024 | 512 | ~50-150* | 63.6 | Free (compute) | Yes |
| all-MiniLM-L6-v2 | ONNX/Local | 384 | 256 | ~200-800* | 56.3 | Free (compute) | Yes |
| all-mpnet-base-v2 | ONNX/Local | 768 | 384 | ~100-400* | 57.8 | Free (compute) | Yes |

*Local model speed varies significantly based on hardware (CPU vs GPU, VRAM, batch size).

## Azure OpenAI Models

### text-embedding-3-small (Recommended for Cloud)

The best balance of quality, speed, and cost for cloud deployments.

```csharp
kernelBuilder.AddAzureOpenAITextEmbeddingGeneration(
    deploymentName: "text-embedding-3-small",
    endpoint: configuration["AzureOpenAI:Endpoint"]!,
    apiKey: configuration["AzureOpenAI:ApiKey"]!);
```

**Characteristics:**
- 1536 dimensions (configurable down to 256 via API)
- 8191 token context window -- handles large chunks well
- Best cost/quality ratio among Azure OpenAI models
- Supports dimension reduction for storage optimization

**Best for:** General-purpose RAG in Azure environments, most document types.

### text-embedding-3-large

Higher quality at higher cost. Use when retrieval precision is critical.

```csharp
kernelBuilder.AddAzureOpenAITextEmbeddingGeneration(
    deploymentName: "text-embedding-3-large",
    endpoint: configuration["AzureOpenAI:Endpoint"]!,
    apiKey: configuration["AzureOpenAI:ApiKey"]!);
```

**Characteristics:**
- 3072 dimensions (configurable down to 256)
- Approximately 3.7% better on MTEB benchmarks vs small variant
- 6.5x more expensive than text-embedding-3-small
- Higher storage requirements in vector store

**Best for:** High-stakes domains (legal, medical, federal policy) where retrieval precision justifies the cost.

### text-embedding-ada-002 (Legacy)

Previous generation. Use only for backward compatibility with existing indexes.

**Characteristics:**
- 1536 dimensions (not configurable)
- 5x more expensive than text-embedding-3-small for lower quality
- No dimension reduction support

**Recommendation:** Migrate to text-embedding-3-small. Requires full re-indexing.

### Government Cloud Configuration

For FedRAMP-authorized deployments:

```csharp
// Azure Government endpoints use .azure.us
kernelBuilder.AddAzureOpenAITextEmbeddingGeneration(
    deploymentName: configuration["AzureOpenAI:EmbeddingDeployment"]!,
    endpoint: "https://your-resource.openai.azure.us/",
    apiKey: configuration["AzureOpenAI:ApiKey"]!);
```

**Note:** Not all embedding models are available in all government regions. Check Azure Government model availability before designing the pipeline.

## Ollama Local Models

### nomic-embed-text (Recommended for Air-Gapped)

Best general-purpose local embedding model. Strong quality with a large context window.

```csharp
kernelBuilder.AddOllamaTextEmbeddingGeneration(
    modelId: "nomic-embed-text",
    endpoint: new Uri("http://localhost:11434"));
```

**Characteristics:**
- 768 dimensions
- 8192 token context window -- matches cloud model capacity
- ~270MB model size
- Good quality/speed tradeoff on CPU
- VRAM requirement: ~1GB (GPU) or runs well on CPU

**Best for:** Air-gapped deployments, development environments, privacy-sensitive data.

### mxbai-embed-large

Higher quality local model with limited context window.

```csharp
kernelBuilder.AddOllamaTextEmbeddingGeneration(
    modelId: "mxbai-embed-large",
    endpoint: new Uri("http://localhost:11434"));
```

**Characteristics:**
- 1024 dimensions
- 512 token context window -- requires smaller chunks
- ~670MB model size
- Higher quality on MTEB benchmarks than nomic-embed-text
- VRAM requirement: ~2GB (GPU)

**Best for:** When retrieval quality justifies the smaller context window and higher resource usage.

**Warning:** The 512-token limit means chunk sizes must be kept under ~2000 characters. This is a significant constraint for documents with long paragraphs.

## ONNX Runtime Models (sentence-transformers)

For .NET applications that need fully embedded (in-process) inference without Ollama.

### all-MiniLM-L6-v2

Fastest local model. Good for development and CPU-only environments.

```csharp
// Using Microsoft.ML.OnnxRuntime for in-process inference
// Requires ONNX-exported model and custom embedding service
public class OnnxEmbeddingService : ITextEmbeddingGenerationService
{
    private readonly InferenceSession _session;

    public OnnxEmbeddingService(string modelPath)
    {
        _session = new InferenceSession(modelPath);
    }

    public async Task<IList<ReadOnlyMemory<float>>> GenerateEmbeddingsAsync(
        IList<string> data, Kernel? kernel = null, CancellationToken ct = default)
    {
        // Tokenize inputs, run inference, return embeddings
        // Implementation depends on tokenizer and model architecture
        throw new NotImplementedException("See ONNX Runtime documentation");
    }
}
```

**Characteristics:**
- 384 dimensions -- smallest storage footprint
- 256 token context window -- requires aggressive chunking
- ~80MB model size
- Fastest inference of any local model
- Runs well on CPU without GPU

**Best for:** Development/testing, very resource-constrained environments, when speed trumps quality.

### all-mpnet-base-v2

Better quality than MiniLM with moderate resource requirements.

**Characteristics:**
- 768 dimensions
- 384 token context window
- ~420MB model size
- Significantly better quality than MiniLM on most benchmarks
- Reasonable CPU performance

**Best for:** Production local deployments where Ollama is not available.

## Selection Decision Tree

```
What is the deployment environment?
|
+-- Cloud (Azure) with internet access?
|   |
|   +-- Cost-sensitive?
|   |   --> text-embedding-3-small (best cost/quality)
|   |
|   +-- Quality is paramount?
|       --> text-embedding-3-large
|
+-- Air-gapped / no cloud access?
|   |
|   +-- Ollama available?
|   |   |
|   |   +-- Documents have long paragraphs?
|   |   |   --> nomic-embed-text (8192 token context)
|   |   |
|   |   +-- Short documents, quality matters?
|   |       --> mxbai-embed-large (better MTEB, 512 token limit)
|   |
|   +-- No Ollama, need in-process?
|       |
|       +-- CPU only, speed matters?
|       |   --> all-MiniLM-L6-v2 (ONNX)
|       |
|       +-- GPU available, quality matters?
|           --> all-mpnet-base-v2 (ONNX)
|
+-- Development / prototyping?
    --> nomic-embed-text via Ollama (easy setup, good quality)
```

## Chunk Size Alignment

The embedding model's max token limit constrains chunk size. Chunks that exceed the limit are silently truncated, destroying semantic meaning.

| Model | Max Tokens | Safe Chunk Size (chars)* | Overlap (chars) |
|-------|-----------|-------------------------|-----------------|
| text-embedding-3-small | 8191 | 6000 | 600 |
| text-embedding-3-large | 8191 | 6000 | 600 |
| nomic-embed-text | 8192 | 6000 | 600 |
| mxbai-embed-large | 512 | 1800 | 200 |
| all-MiniLM-L6-v2 | 256 | 900 | 100 |
| all-mpnet-base-v2 | 384 | 1400 | 150 |

*Assumes ~4 characters per token for English text, with 10% safety margin.

## FIPS Compliance Notes

For federal deployments requiring FIPS 140-2/3 compliance:

- **Azure OpenAI models** in government regions operate on FIPS-validated infrastructure
- **Ollama local models** run on customer-managed infrastructure -- FIPS compliance depends on the host OS and cryptographic libraries
- **ONNX Runtime models** similarly depend on the host environment
- When FIPS mode is required on the host OS, verify that the embedding inference pipeline does not use non-compliant cryptographic operations (this is primarily a concern for TLS connections to Ollama or Azure endpoints, not for the embedding math itself)

## Performance Benchmarking

When selecting an embedding model, benchmark on your actual corpus:

```csharp
public async Task<EmbeddingBenchmark> BenchmarkEmbeddingModel(
    ITextEmbeddingGenerationService embeddings,
    List<string> sampleTexts)
{
    var stopwatch = Stopwatch.StartNew();

    var results = await embeddings.GenerateEmbeddingsAsync(sampleTexts);

    stopwatch.Stop();

    return new EmbeddingBenchmark
    {
        ModelName = embeddings.GetType().Name,
        DocumentCount = sampleTexts.Count,
        TotalTimeMs = stopwatch.ElapsedMilliseconds,
        DocsPerSecond = sampleTexts.Count / (stopwatch.ElapsedMilliseconds / 1000.0),
        Dimensions = results.First().Length,
        AvgCharsPerDoc = sampleTexts.Average(t => t.Length)
    };
}

public record EmbeddingBenchmark
{
    public string ModelName { get; init; } = "";
    public int DocumentCount { get; init; }
    public long TotalTimeMs { get; init; }
    public double DocsPerSecond { get; init; }
    public int Dimensions { get; init; }
    public double AvgCharsPerDoc { get; init; }
}
```

See also: `vector-store-options.md` for vector store dimension requirements and `federal-ai-compliance.md` for full federal compliance guidance.
