using Microsoft.Extensions.Diagnostics.HealthChecks;
using MyApi.Data;

namespace MyApi.Infrastructure;

// 「DB 連得上」不等於「DB 的 Schema 跟程式碼對得上」（部署死因 3）：
// 這個檢查比對程式碼裡有的 Migration 和資料庫已套用的，還有沒套的就回 Unhealthy
public class SchemaHealthCheck(AppDbContext db) : IHealthCheck
{
    public async Task<HealthCheckResult> CheckHealthAsync(HealthCheckContext context, CancellationToken ct = default)
    {
        var (_, pending) = await MigrationState.GetAsync(db, ct);
        return pending.Count == 0
            ? HealthCheckResult.Healthy("Schema 是最新版")
            : HealthCheckResult.Unhealthy($"還有 {pending.Count} 個 Migration 沒套用：{string.Join(", ", pending)}");
    }
}
