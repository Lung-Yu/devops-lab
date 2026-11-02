using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using Npgsql;

namespace MyApi.Infrastructure;

// 資料庫出問題時，回給畫面「看得懂的原因＋追蹤編號」，完整錯誤只寫在 log（Module 5）
public class DbExceptionHandler(IProblemDetailsService problems, ILogger<DbExceptionHandler> log) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(HttpContext http, Exception ex, CancellationToken ct)
    {
        var (title, detail) = Unwrap(ex) switch
        {
            // 42P01 = 資料表不存在：多半是這個環境還沒跑 migrate
            PostgresException { SqlState: "42P01" } => ("資料庫 Schema 不是最新版", "這個環境可能還沒執行 migrate"),
            // 3D000 = 資料庫不存在：DB_NAME 打錯
            PostgresException { SqlState: "3D000" } => ("找不到資料庫", "請檢查 DB_NAME 設定"),
            // 28P01 = 帳密錯誤
            PostgresException { SqlState: "28P01" } => ("資料庫帳號或密碼錯誤", "請檢查 DB_USER／DB_PASSWORD 設定"),
            NpgsqlException => ("資料庫連不上", "請檢查 DB_HOST／DB_PORT 與網路"),
            _ => (null, null),
        };
        if (title is null) return false;   // 其他錯誤交給預設處理（500）

        log.LogError(ex, "資料庫錯誤：{Title}", title);
        http.Response.StatusCode = StatusCodes.Status503ServiceUnavailable;
        return await problems.TryWriteAsync(new ProblemDetailsContext
        {
            HttpContext = http,
            Exception = ex,
            ProblemDetails = new ProblemDetails { Status = 503, Title = title, Detail = detail },
        });
    }

    static Exception Unwrap(Exception ex)
    {
        for (var e = ex; e is not null; e = e.InnerException)
            if (e is NpgsqlException) return e;
        return ex;
    }
}
