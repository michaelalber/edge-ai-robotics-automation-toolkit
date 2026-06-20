# Federal AI Compliance for RAG Systems

## Overview

RAG systems deployed in federal environments must comply with multiple frameworks:
- NIST AI Risk Management Framework (AI RMF)
- Executive Order 14110 on Safe, Secure, and Trustworthy AI
- FedRAMP for cloud services
- Agency-specific requirements (DOE, DOD, etc.)

## Data Classification

### Classification Levels

| Level | Description | RAG Eligibility |
|-------|-------------|-----------------|
| Unclassified | Public or internal data | Full RAG capability |
| CUI | Controlled Unclassified Information | Limited RAG with controls |
| Classified | Secret, Top Secret, etc. | NOT eligible for RAG |

### CUI Handling Requirements

```csharp
public class CuiRagService : IRagService
{
    private readonly IRagService _inner;
    private readonly ICuiValidator _cuiValidator;
    private readonly IAuditService _audit;

    public async Task<string> AskAsync(string question, string collection, CancellationToken ct)
    {
        // 1. Validate question doesn't request classified info
        var questionClassification = await _cuiValidator.ClassifyQueryAsync(question);
        if (questionClassification == Classification.Classified)
        {
            await _audit.LogBlockedQueryAsync(question, "Classified query attempt");
            throw new SecurityException("Query appears to request classified information");
        }

        // 2. Get response
        var response = await _inner.AskAsync(question, collection, ct);

        // 3. Validate response doesn't leak sensitive data
        var responseClassification = await _cuiValidator.ClassifyResponseAsync(response);
        if (responseClassification > Classification.CUI)
        {
            await _audit.LogBlockedResponseAsync(question, "Response contained classified info");
            throw new SecurityException("Response contained potentially classified information");
        }

        // 4. Apply CUI markings if needed
        if (responseClassification == Classification.CUI)
        {
            response = ApplyCuiMarkings(response);
        }

        // 5. Log successful query
        await _audit.LogSuccessfulQueryAsync(question, responseClassification);

        return response;
    }

    private string ApplyCuiMarkings(string response)
    {
        return $"""
            //CUI//
            {response}
            //CUI//
            """;
    }
}
```

## FedRAMP Requirements

### Authorized Cloud Services

For FedRAMP compliance, use only authorized services:

| Service | FedRAMP Status | Notes |
|---------|----------------|-------|
| Azure OpenAI | FedRAMP High | Government regions |
| Azure AI Search | FedRAMP High | Government regions |
| Azure SQL | FedRAMP High | With appropriate SKU |
| AWS Bedrock | FedRAMP High | GovCloud |

### Configuration for Government Cloud

```csharp
// Azure Government configuration
kernelBuilder.AddAzureOpenAIChatCompletion(
    deploymentName: configuration["AzureOpenAI:ChatDeployment"]!,
    endpoint: "https://your-resource.openai.azure.us/",  // .azure.us for Gov
    apiKey: configuration["AzureOpenAI:ApiKey"]!);
```

## NIST AI RMF Compliance

### Governance

```csharp
public class GovernedRagService : IRagService
{
    // Map to NIST AI RMF categories

    // GOVERN: Policies and procedures
    private readonly RagPolicies _policies;

    // MAP: Risk identification
    private readonly IRiskAssessment _riskAssessment;

    // MEASURE: Performance monitoring
    private readonly IMetricsService _metrics;

    // MANAGE: Risk mitigation
    private readonly IRiskMitigation _mitigation;

    public async Task<string> AskAsync(string question, string collection, CancellationToken ct)
    {
        // GOVERN: Check policy compliance
        if (!_policies.IsQueryAllowed(question))
        {
            return "This query is not permitted by organizational policy.";
        }

        // MAP: Assess risk level
        var riskLevel = await _riskAssessment.AssessQueryRiskAsync(question);
        if (riskLevel == RiskLevel.High)
        {
            await RequestHumanReviewAsync(question);
        }

        // Execute query
        var response = await _inner.AskAsync(question, collection, ct);

        // MEASURE: Record metrics
        await _metrics.RecordQueryAsync(new QueryMetrics
        {
            Question = question,
            ResponseLength = response.Length,
            RiskLevel = riskLevel,
            Timestamp = DateTime.UtcNow
        });

        // MANAGE: Apply mitigations
        response = await _mitigation.ApplyMitigationsAsync(response, riskLevel);

        return response;
    }
}
```

### Transparency Requirements

```csharp
public class TransparentRagResponse
{
    public string Answer { get; set; } = string.Empty;

    // NIST AI RMF transparency requirements
    public string[] SourceDocuments { get; set; } = Array.Empty<string>();
    public double[] ConfidenceScores { get; set; } = Array.Empty<double>();
    public string ModelVersion { get; set; } = string.Empty;
    public DateTime ProcessedAt { get; set; }
    public string[] Limitations { get; set; } = Array.Empty<string>();

    public static TransparentRagResponse Create(
        string answer,
        IEnumerable<MemoryQueryResult> sources,
        string modelVersion)
    {
        return new TransparentRagResponse
        {
            Answer = answer,
            SourceDocuments = sources.Select(s => s.Metadata.Description).ToArray(),
            ConfidenceScores = sources.Select(s => s.Relevance).ToArray(),
            ModelVersion = modelVersion,
            ProcessedAt = DateTime.UtcNow,
            Limitations = new[]
            {
                "Response is generated based on available documents only",
                "Information may not reflect recent updates",
                "Should not be used for classified decisions"
            }
        };
    }
}
```

## Audit Logging Requirements

### Comprehensive Audit Trail

```csharp
public class FederalAuditLogger : IAuditLogger
{
    private readonly AppDbContext _db;
    private readonly ICurrentUser _currentUser;

    public async Task LogQueryAsync(RagQueryAuditRecord record)
    {
        var audit = new AuditLog
        {
            // Who
            UserId = _currentUser.Id,
            UserEmail = _currentUser.Email,
            UserOrganization = _currentUser.Organization,

            // What
            Action = "RAG_QUERY",
            QueryHash = ComputeHash(record.Question),  // Don't store raw query if sensitive
            Collection = record.Collection,
            ResultCount = record.ResultCount,
            ResponseLength = record.ResponseLength,

            // When
            Timestamp = DateTime.UtcNow,

            // Where
            SourceIp = _currentUser.IpAddress,
            UserAgent = _currentUser.UserAgent,

            // Context
            ClassificationLevel = record.Classification.ToString(),
            RiskLevel = record.RiskLevel.ToString(),
            WasBlocked = record.WasBlocked,
            BlockReason = record.BlockReason
        };

        _db.AuditLogs.Add(audit);
        await _db.SaveChangesAsync();
    }

    // Compute non-reversible hash for sensitive queries
    private static string ComputeHash(string input)
    {
        using var sha256 = SHA256.Create();
        var bytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(input));
        return Convert.ToBase64String(bytes);
    }
}

public class AuditLog
{
    public long Id { get; set; }

    // Identity
    public string UserId { get; set; } = string.Empty;
    public string UserEmail { get; set; } = string.Empty;
    public string? UserOrganization { get; set; }

    // Action
    public string Action { get; set; } = string.Empty;
    public string? QueryHash { get; set; }
    public string? Collection { get; set; }
    public int ResultCount { get; set; }
    public int ResponseLength { get; set; }

    // Timing
    public DateTime Timestamp { get; set; }

    // Location
    public string? SourceIp { get; set; }
    public string? UserAgent { get; set; }

    // Classification
    public string? ClassificationLevel { get; set; }
    public string? RiskLevel { get; set; }
    public bool WasBlocked { get; set; }
    public string? BlockReason { get; set; }
}
```

## Access Control

### Role-Based Access to Collections

```csharp
public class SecureRagService : IRagService
{
    private readonly IAuthorizationService _authz;
    private readonly ICurrentUser _user;

    public async Task<string> AskAsync(string question, string collection, CancellationToken ct)
    {
        // Check user has access to collection
        var authResult = await _authz.AuthorizeAsync(
            _user.Principal,
            collection,
            new CollectionAccessRequirement());

        if (!authResult.Succeeded)
        {
            throw new UnauthorizedAccessException(
                $"User {_user.Id} does not have access to collection {collection}");
        }

        return await _inner.AskAsync(question, collection, ct);
    }
}

public class CollectionAccessRequirement : IAuthorizationRequirement { }

public class CollectionAccessHandler : AuthorizationHandler<CollectionAccessRequirement, string>
{
    protected override Task HandleRequirementAsync(
        AuthorizationHandlerContext context,
        CollectionAccessRequirement requirement,
        string collection)
    {
        // Check if user's clearance level allows access to collection
        var userClearance = context.User.FindFirst("clearance_level")?.Value;
        var requiredClearance = GetCollectionClearance(collection);

        if (ClearanceMeetsRequirement(userClearance, requiredClearance))
        {
            context.Succeed(requirement);
        }

        return Task.CompletedTask;
    }
}
```

## Air-Gapped Deployment

For disconnected environments:

```csharp
// Use local models (no external API calls)
public static class AirGappedConfiguration
{
    public static IKernelBuilder AddLocalAI(this IKernelBuilder builder, IConfiguration config)
    {
        // Local LLM via Ollama
        builder.AddOllamaChatCompletion(
            modelId: config["LocalAI:ChatModel"] ?? "llama3",
            endpoint: new Uri(config["LocalAI:Endpoint"] ?? "http://localhost:11434"));

        // Local embeddings
        builder.AddOllamaTextEmbeddingGeneration(
            modelId: config["LocalAI:EmbeddingModel"] ?? "nomic-embed-text",
            endpoint: new Uri(config["LocalAI:Endpoint"] ?? "http://localhost:11434"));

        return builder;
    }
}

// Local vector store (no cloud)
public static ISemanticTextMemory CreateLocalMemory(ITextEmbeddingGenerationService embeddings)
{
    // Use PostgreSQL with pgvector on local server
    return new MemoryBuilder()
        .WithPostgresMemoryStore(
            connectionString: "Host=localhost;Database=rag;Username=rag_user;Password=...",
            vectorSize: 768,
            schema: "embeddings")
        .WithTextEmbeddingGeneration(embeddings)
        .Build();
}
```

## Incident Response

```csharp
public class IncidentDetector
{
    private readonly ILogger<IncidentDetector> _logger;
    private readonly IAlertService _alerts;

    public async Task MonitorQueryAsync(RagQuery query, RagResponse response)
    {
        // Detect potential incidents

        // 1. Data exfiltration attempt
        if (IsDataExfiltrationAttempt(query))
        {
            await _alerts.RaiseAlertAsync(new SecurityAlert
            {
                Type = AlertType.DataExfiltration,
                Severity = Severity.High,
                UserId = query.UserId,
                Details = "Possible data exfiltration attempt detected"
            });
        }

        // 2. Classification spillage
        if (await ContainsHigherClassificationAsync(response))
        {
            await _alerts.RaiseAlertAsync(new SecurityAlert
            {
                Type = AlertType.ClassificationSpillage,
                Severity = Severity.Critical,
                Details = "Response may contain higher classification data"
            });
        }

        // 3. Anomalous query patterns
        if (await IsAnomalousPatternAsync(query))
        {
            await _alerts.RaiseAlertAsync(new SecurityAlert
            {
                Type = AlertType.AnomalousActivity,
                Severity = Severity.Medium,
                UserId = query.UserId,
                Details = "Unusual query pattern detected"
            });
        }
    }
}
```

## Compliance Checklist

- [ ] Data classification policy defined and implemented
- [ ] Only FedRAMP-authorized services used
- [ ] CUI handling procedures in place
- [ ] Comprehensive audit logging enabled
- [ ] Role-based access control implemented
- [ ] Transparency requirements met (sources, confidence, limitations)
- [ ] Incident response procedures defined
- [ ] Regular security assessments scheduled
- [ ] User training completed
- [ ] Air-gapped option available for sensitive environments
