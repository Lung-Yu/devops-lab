using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Storage;

namespace MyApi.Data;

// `docker run ... keypasco-lab-api migrate` 走這裡：Schema 變更是部署流程裡獨立的一步，
// 不在服務啟動時偷偷做（多台同時啟動會搶著改 Schema；改失敗服務也起不來）
public static class DbSetup
{
    public static async Task<int> MigrateAsync(IServiceProvider services, IConfiguration config)
    {
        using var scope = services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var log = scope.ServiceProvider.GetRequiredService<ILoggerFactory>().CreateLogger("Migrate");
        try
        {
            // EF Core 的 Migrate 遇到不存在的資料庫會自己建一個新的空庫：DB_NAME 打錯字就默默多出一個庫。
            // 部署工具不該這麼「貼心」——找不到就失敗，讓人去查設定
            if (!await db.GetService<IRelationalDatabaseCreator>().ExistsAsync())
            {
                log.LogCritical("找不到資料庫 {Database}（{Host}:{Port}），請確認 DB_NAME；migrate 不會自動建立資料庫",
                    config["DB_NAME"], config["DB_HOST"], config["DB_PORT"]);
                return 1;
            }

            var (applied, pending) = await MigrationState.GetAsync(db);
            log.LogInformation("資料庫 {Database}：已套用 {AppliedCount} 個，待套用 {PendingCount} 個 {Pending}",
                config["DB_NAME"], applied.Count, pending.Count, string.Join(", ", pending));

            await db.Database.MigrateAsync();
            await SeedAsync(db, config, log);
            log.LogInformation("Migration 完成，目前版本 {Version}", pending.LastOrDefault() ?? applied.LastOrDefault());
            return 0;
        }
        catch (Exception ex)
        {
            log.LogCritical(ex, "Migration 失敗，資料庫 {Host}:{Port}/{Database}", config["DB_HOST"], config["DB_PORT"], config["DB_NAME"]);
            return 1;
        }
    }

    // 課堂用的初始帳號與範例資料：只在資料表是空的時候建。
    // 正式環境不要有預設密碼——第一個管理員應該由部署人員用一次性指令建立。
    static async Task SeedAsync(AppDbContext db, IConfiguration config, ILogger log)
    {
        if (await db.Users.AnyAsync()) return;

        var password = config["SEED_PASSWORD"] ?? "Lab@2026";
        var hasher = new PasswordHasher<User>();
        User Make(string name, string display, string role)
        {
            var u = new User { UserName = name, DisplayName = display, Role = role };
            u.PasswordHash = hasher.HashPassword(u, password);
            return u;
        }
        db.Users.AddRange(
            Make("admin", "系統管理員", Roles.Admin),
            Make("engineer", "部署工程師", Roles.Engineer),
            Make("viewer", "專案經理", Roles.Viewer));

        var now = DateTime.UtcNow;
        db.Deployments.AddRange(
            new Deployment { Customer = "客戶 A 銀行", Environment = "POC", Version = "2.3.0", Status = "Failed", Note = "防火牆沒開 5432，DB 連不上", DeployedAt = now.AddDays(-9), CreatedBy = "engineer" },
            new Deployment { Customer = "客戶 A 銀行", Environment = "POC", Version = "2.3.0", Status = "Succeeded", Note = "網路開通後重新部署", DeployedAt = now.AddDays(-8), CreatedBy = "engineer" },
            new Deployment { Customer = "客戶 B 證券", Environment = "QA", Version = "2.4.0-rc1", Status = "Succeeded", DeployedAt = now.AddDays(-3), CreatedBy = "engineer" },
            new Deployment { Customer = "客戶 C 醫院", Environment = "POC", Version = "2.4.0", Status = "Planned", Note = "Windows Server + IIS", DeployedAt = now.AddDays(2), CreatedBy = "admin" });
        await db.SaveChangesAsync();
        log.LogWarning("已建立預設帳號 admin／engineer／viewer（課堂用預設密碼，正式環境請勿使用）");
    }
}
