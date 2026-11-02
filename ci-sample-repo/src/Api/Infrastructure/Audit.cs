using System.Diagnostics;
using System.Security.Claims;
using MyApi.Data;

namespace MyApi.Infrastructure;

public static class Audit
{
    // 跟業務資料同一個 SaveChanges 寫入：資料改成功、稽核紀錄就一定在
    public static void Add(AppDbContext db, ClaimsPrincipal user, string action, string? target = null) =>
        db.AuditLogs.Add(new AuditLog
        {
            UserName = user.Identity?.Name ?? "anonymous",
            Action = action,
            Target = target,
            TraceId = Activity.Current?.TraceId.ToString(),
        });
}
