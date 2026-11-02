using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace MyApi.Data;

// 程式碼裡有哪些 Migration、資料庫套用了哪些：兩邊一比就知道 Schema 是不是最新版
public static class MigrationState
{
    public static async Task<(List<string> Applied, List<string> Pending)> GetAsync(AppDbContext db, CancellationToken ct = default)
    {
        // 全新的資料庫連紀錄表（__EFMigrationsHistory）都還沒有：先確認，避免查一張不存在的表
        var history = db.GetService<IHistoryRepository>();
        var applied = await history.ExistsAsync(ct)
            ? (await history.GetAppliedMigrationsAsync(ct)).Select(m => m.MigrationId).ToList()
            : [];
        var pending = db.Database.GetMigrations().Except(applied).ToList();
        return (applied, pending);
    }
}
