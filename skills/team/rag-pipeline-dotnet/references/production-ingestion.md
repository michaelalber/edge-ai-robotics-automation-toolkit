# Production RAG Ingestion Hardening (.NET / Semantic Kernel)

Eight patterns for building ingestion pipelines that survive real corpora: incremental updates,
memory safety, structural fidelity, and crash resilience. Patterns are Semantic Kernel-compatible
but apply to any .NET vector store abstraction.

---

## 1. Incremental Ingestion with Hash-Based Change Detection

Re-processing the entire corpus on every update is not a strategy. Persist a manifest that maps
each source file to its SHA-256 hash and chunk IDs; skip files that have not changed.

```csharp
using System.Security.Cryptography;
using System.Text.Json;

public sealed record ManifestEntry(
    string Path,
    string Sha256,
    DateTimeOffset IngestedAt,
    IReadOnlyList<string> ChunkIds);

public sealed class IngestManifest
{
    private readonly string _manifestPath;
    private Dictionary<string, ManifestEntry> _entries;

    public IngestManifest(string manifestPath)
    {
        _manifestPath = manifestPath;
        _entries = File.Exists(manifestPath)
            ? JsonSerializer.Deserialize<Dictionary<string, ManifestEntry>>(
                  File.ReadAllText(manifestPath)) ?? new()
            : new();
    }

    public bool IsChanged(string filePath)
    {
        var hash = ComputeSha256(filePath);
        return !_entries.TryGetValue(filePath, out var entry) || entry.Sha256 != hash;
    }

    public IReadOnlyList<string> GetChunkIds(string filePath) =>
        _entries.TryGetValue(filePath, out var entry) ? entry.ChunkIds : [];

    public void Record(string filePath, IReadOnlyList<string> chunkIds) =>
        _entries[filePath] = new ManifestEntry(
            filePath, ComputeSha256(filePath), DateTimeOffset.UtcNow, chunkIds);

    public void Save() =>
        File.WriteAllText(_manifestPath, JsonSerializer.Serialize(_entries,
            new JsonSerializerOptions { WriteIndented = true }));

    private static string ComputeSha256(string filePath)
    {
        using var stream = File.OpenRead(filePath);
        return Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
    }
}
```

---

## 2. Chunk Lifecycle Management

When a document changes, its stale chunks must be deleted before new ones are added. Without
deletion, both old and new chunks appear in retrieval — there is no error, just wrong answers.

```csharp
// Semantic Kernel ISemanticTextMemory uses collection + id for deletion
public static async Task DeleteStaleChunksAsync(
    ISemanticTextMemory memory,
    string collection,
    IReadOnlyList<string> staleIds,
    CancellationToken ct = default)
{
    foreach (var id in staleIds)
        await memory.RemoveAsync(collection, id, ct);
}

// Store chunks with deterministic IDs so the manifest can track them
public static async Task<List<string>> StoreChunksAsync(
    ISemanticTextMemory memory,
    string collection,
    IReadOnlyList<(string Text, string Description, IDictionary<string, string> Metadata)> chunks,
    CancellationToken ct = default)
{
    var ids = new List<string>();
    foreach (var (text, description, metadata) in chunks)
    {
        var id = Guid.NewGuid().ToString();
        await memory.SaveInformationAsync(collection, text, id, description,
            additionalMetadata: JsonSerializer.Serialize(metadata), cancellationToken: ct);
        ids.Add(id);
    }
    return ids;
}
```

> Qdrant and pgvector support batch deletion by ID list — prefer batch APIs for large stale sets
> rather than iterating individual removes.

---

## 3. Memory-Bounded Batch Streaming

Embedding 50,000 chunks at once holds all vectors in memory before any are persisted.
Process in batches: embed a batch, store it, release it.

```csharp
public static async Task<List<string>> StoreChunksBatchedAsync(
    ISemanticTextMemory memory,
    string collection,
    IReadOnlyList<(string Text, string Description, IDictionary<string, string> Metadata)> chunks,
    int batchSize = 50,
    CancellationToken ct = default)
{
    var allIds = new List<string>(chunks.Count);
    for (int i = 0; i < chunks.Count; i += batchSize)
    {
        var batch = chunks.Skip(i).Take(batchSize).ToList();
        var batchIds = await StoreChunksAsync(memory, collection, batch, ct);
        allIds.AddRange(batchIds);
        // batch goes out of scope — memory released before next iteration
    }
    return allIds;
}
```

**Batch size guidance:** 16–32 for CPU-only deployments · 32–64 for standard GPU · 64–128 for
high-VRAM servers. Start at 32 and double until OOM, then halve. Long documents (legal,
manuals) warrant smaller batches.

---

## 4. Crash-Resilient State Persistence

Save the manifest after every successfully processed file. Ingesting thousands of documents
takes time — a crash mid-run should resume from where it stopped.

```csharp
public async Task IngestIncrementallyAsync(
    string sourceDir,
    string collection,
    ISemanticTextMemory memory,
    IngestManifest manifest,
    CancellationToken ct = default)
{
    var files = Directory.EnumerateFiles(sourceDir, "*.*", SearchOption.AllDirectories)
        .Where(f => !ShouldSkip(f) && manifest.IsChanged(f))
        .ToList();

    foreach (var filePath in files)
    {
        try
        {
            var staleIds = manifest.GetChunkIds(filePath);
            if (staleIds.Count > 0)
                await DeleteStaleChunksAsync(memory, collection, staleIds, ct);

            var text = await GetDocumentTextAsync(filePath);
            if (string.IsNullOrWhiteSpace(text)) continue;

            var chunks = ChunkDocument(text, filePath);
            var chunkIds = await StoreChunksBatchedAsync(memory, collection, chunks, ct: ct);

            manifest.Record(filePath, chunkIds);
            manifest.Save();  // per-file save — survives crash at any point
        }
        catch (Exception ex)
        {
            // No manifest.Record — file will retry on next run
            _logger.LogError(ex, "Failed to ingest {FilePath}", filePath);
        }
    }
}
```

---

## 5. Heading Context as Chunk Metadata

A chunk reading "Returns null if not found" is ambiguous. That same chunk tagged
`heading_context: ["API Reference", "UserService", "GetUser"]` is precise. Structural location
improves retrieval quality and gives the LLM meaningful context alongside the content.

```csharp
using System.Text.RegularExpressions;

public static partial class HeadingContext
{
    [GeneratedRegex(@"^(#{1,6})\s+(.+)$", RegexOptions.Multiline)]
    private static partial Regex HeadingPattern();

    public static List<string> GetContextAtOffset(string markdown, int charOffset)
    {
        var stack = new List<(int Level, string Text)>();
        foreach (Match match in HeadingPattern().Matches(markdown))
        {
            if (match.Index > charOffset) break;
            int level = match.Groups[1].Length;
            string text = match.Groups[2].Value.Trim();
            stack.RemoveAll(h => h.Level >= level);
            stack.Add((level, text));
        }
        return stack.Select(h => h.Text).ToList();
    }
}
```

Store `heading_context` as serialized JSON in the chunk's `additionalMetadata` field so it
appears in retrieved results and can be formatted for the LLM context.

---

## 6. Table Atomicity

Splitting a Markdown or HTML table mid-row produces semantically useless chunks. Detect tables
before chunking and treat them as atomic units — never split, regardless of size.

```csharp
public static partial class TableDetector
{
    [GeneratedRegex(@"\|.+\|\n\|[-| :]+\|\n(?:\|.+\|\n)*", RegexOptions.Multiline)]
    private static partial Regex MarkdownTable();

    [GeneratedRegex(@"<table[\s\S]*?</table>", RegexOptions.IgnoreCase)]
    private static partial Regex HtmlTable();

    public static IReadOnlyList<(int Start, int End, string Content)> FindTables(string text)
    {
        return MarkdownTable().Matches(text)
            .Concat(HtmlTable().Matches(text))
            .Select(m => (m.Index, m.Index + m.Length, m.Value))
            .OrderBy(t => t.Item1)
            .ToList();
    }
}

public static List<(string Text, bool IsTable)> SplitPreservingTables(string text, int chunkSize)
{
    var tables = TableDetector.FindTables(text);
    if (tables.Count == 0)
        return SplitText(text, chunkSize).Select(t => (t, false)).ToList();

    var result = new List<(string, bool)>();
    int cursor = 0;
    foreach (var (start, end, content) in tables)
    {
        var pre = text[cursor..start];
        if (!string.IsNullOrWhiteSpace(pre))
            result.AddRange(SplitText(pre, chunkSize).Select(t => (t, false)));
        result.Add((content, true));  // table is atomic
        cursor = end;
    }
    var post = text[cursor..];
    if (!string.IsNullOrWhiteSpace(post))
        result.AddRange(SplitText(post, chunkSize).Select(t => (t, false)));
    return result;
}
```

---

## 7. Pre-Flight Quality Gates

Apply before embedding to prevent OOM, noise ingestion, and wasted API calls.

```csharp
private static readonly HashSet<string> ExcludeFilenames = new(StringComparer.OrdinalIgnoreCase)
{
    "CHANGELOG.md", "CHANGELOG", "LICENSE", "LICENSE.md", "LICENSE.txt",
    "CODE_OF_CONDUCT.md", "CONTRIBUTING.md", "NOTICE", "NOTICE.md",
};

private const long MaxFileSizeBytes = 100L * 1024 * 1024; // 100 MB

public static string? ShouldSkip(string filePath)
{
    var info = new FileInfo(filePath);
    if (ExcludeFilenames.Contains(info.Name))
        return $"excluded filename: {info.Name}";
    if (info.Name.StartsWith("CHANGELOG", StringComparison.OrdinalIgnoreCase) ||
        info.Name.StartsWith("release-notes", StringComparison.OrdinalIgnoreCase))
        return $"excluded pattern: {info.Name}";
    if (info.Extension.Equals(".md", StringComparison.OrdinalIgnoreCase) &&
        info.Name.Contains(".pdf."))
        return "sidecar file — skip as primary source";
    if (info.Length > MaxFileSizeBytes)
        return $"too large: {info.Length / (1024 * 1024)} MB";
    return null;
}
```

---

## 8. Markdown Sidecar Pattern

PDF and DOCX extraction is slow. Convert once, save as `<filename>.pdf.md` sidecar, and read
the sidecar on subsequent ingestions. This decouples expensive conversion from fast CPU ingestion.

```csharp
public static async Task<string> GetDocumentTextAsync(
    string filePath,
    IDocumentConverter? converter = null,
    CancellationToken ct = default)
{
    var sidecarPath = filePath + ".md";
    if (File.Exists(sidecarPath))
        return await File.ReadAllTextAsync(sidecarPath, ct);

    if (converter is null)
        return await File.ReadAllTextAsync(filePath, ct);

    var text = await converter.ConvertAsync(filePath, ct);  // expensive
    await File.WriteAllTextAsync(sidecarPath, text, ct);
    return text;
}
```

**Use sidecars for:** PDFs with OCR, DOCX/PPTX with complex layouts, any conversion > 1 s
per document.

**Skip sidecars for:** plain `.md`, `.txt`, `.rst` — no conversion overhead. Rapidly-changing
documents — sidecars go stale; rely on hash-based change detection to invalidate instead.
