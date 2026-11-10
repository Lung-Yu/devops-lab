using System.Diagnostics;
using System.Reflection;
using System.Security.Claims;
using System.Text.Encodings.Web;
using System.Text.Json;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.Extensions.Logging.Console;
using MyApi.Data;
using MyApi.Endpoints;
using MyApi.Infrastructure;

var builder = WebApplication.CreateBuilder(args);
var config = builder.Configuration;

// 設定值的來源（後面蓋前面）：
//   appsettings.json → appsettings.{環境}.json → 環境變數（--env-file 帶進來的）
// 程式碼裡只寫「要哪個設定」，不寫「值是多少」。
var connectionString =
    $"Host={config["DB_HOST"]};Port={config["DB_PORT"]};Database={config["DB_NAME"]};" +
    $"Username={config["DB_USER"]};Password={config["DB_PASSWORD"]};Timeout=3;Gss Encryption Mode=Disable";

// JSON log 裡的中文直接輸出，不轉成 \uXXXX（docker logs 才看得懂）
builder.Services.Configure<JsonConsoleFormatterOptions>(o =>
    o.JsonWriterOptions = new JsonWriterOptions { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping });

// 新資料庫還沒有 __EFMigrationsHistory 時，EF 會先記一筆「SQL 執行失敗」再自己處理掉，看起來像出事其實沒事；
// 關掉這一類，真正的資料庫錯誤由 DbExceptionHandler 和 migrate 指令自己記
builder.Logging.AddFilter("Microsoft.EntityFrameworkCore.Database.Command", LogLevel.Critical);

builder.Services.AddDbContext<AppDbContext>(o => o.UseNpgsql(connectionString));

// Lab M4 步驟四：註冊 Health Check，檢查資料庫連不連得上
// "ready" 標籤的另外加檢查 Schema 版本（Module 6）：/health 看「活著沒」，/health/ready 看「能不能接客」
builder.Services.AddHealthChecks()
    .AddNpgSql(connectionString, name: "database", failureStatus: HealthStatus.Unhealthy, tags: ["ready"])
    .AddCheck<SchemaHealthCheck>("schema", tags: ["ready"]);

// 登入：Cookie（HttpOnly，前端 JavaScript 讀不到）；API 未登入回 401、沒權限回 403，不轉址到登入頁
builder.Services.AddAuthentication(CookieAuthenticationDefaults.AuthenticationScheme)
    .AddCookie(o =>
    {
        o.Cookie.Name = "lab.auth";
        o.Cookie.HttpOnly = true;
        o.Cookie.SameSite = SameSiteMode.Strict;   // 別的網站送來的請求不帶這個 cookie（擋 CSRF）
        o.ExpireTimeSpan = TimeSpan.FromHours(8);
        o.SlidingExpiration = true;
        o.Events.OnRedirectToLogin = ctx => { ctx.Response.StatusCode = 401; return Task.CompletedTask; };
        o.Events.OnRedirectToAccessDenied = ctx => { ctx.Response.StatusCode = 403; return Task.CompletedTask; };
        // 每個請求都回資料庫確認：帳號被停用或改了角色，馬上生效，不用等 cookie 過期
        o.Events.OnValidatePrincipal = async ctx =>
        {
            var db = ctx.HttpContext.RequestServices.GetRequiredService<AppDbContext>();
            var principal = ctx.Principal!;
            var id = int.Parse(principal.FindFirstValue(ClaimTypes.NameIdentifier)!);
            var user = await db.Users.AsNoTracking().SingleOrDefaultAsync(u => u.Id == id);
            if (user is not { IsActive: true } || user.Role != principal.FindFirstValue(ClaimTypes.Role))
            {
                ctx.RejectPrincipal();
                await ctx.HttpContext.SignOutAsync(CookieAuthenticationDefaults.AuthenticationScheme);
            }
        };
    });

// 權限規則集中定義：端點只寫「要哪條規則」，不在各處散落 if (role == ...)
builder.Services.AddAuthorizationBuilder()
    .AddPolicy("CanEdit", p => p.RequireRole(Roles.Admin, Roles.Engineer))
    .AddPolicy("AdminOnly", p => p.RequireRole(Roles.Admin));

// 錯誤回應統一格式（RFC 9457 Problem Details），帶 traceId 讓使用者回報、維運查 log（Module 5）
builder.Services.AddProblemDetails(o => o.CustomizeProblemDetails = ctx =>
    ctx.ProblemDetails.Extensions["traceId"] = Activity.Current?.TraceId.ToString() ?? ctx.HttpContext.TraceIdentifier);
builder.Services.AddExceptionHandler<DbExceptionHandler>();

var app = builder.Build();

// Module 6：`docker run ... keypasco-lab-api migrate` 只做 Schema 升級就結束，不啟動網站
if (args.FirstOrDefault() == "migrate")
    return await DbSetup.MigrateAsync(app.Services, config);

app.UseExceptionHandler();
app.UseStatusCodePages();

// 每個回應都帶 X-Trace-Id：畫面上的錯誤訊息、瀏覽器開發者工具、伺服器 log 用同一個編號對得起來
app.Use(async (ctx, next) =>
{
    ctx.Response.Headers["X-Trace-Id"] = Activity.Current?.TraceId.ToString();
    await next();
});

app.UseDefaultFiles();
app.UseStaticFiles();     // 前端（Vue 建置後的檔案）放在 wwwroot，跟 API 同一個 image、同一個網址
app.UseAuthentication();
app.UseAuthorization();

// Lab M2：回報「我現在吃到的是哪一組設定」
// （教學用，所以不用登入；正式系統不要對外公開主機名稱這類資訊）
app.MapGet("/whoami", () => new
{
    environment = app.Environment.EnvironmentName,  // 來自 ASPNETCORE_ENVIRONMENT
    dbHost = config["DB_HOST"],
    dbName = config["DB_NAME"]
});

// DB 正常回 200 Healthy；DB 斷線回 503 Unhealthy
app.MapHealthChecks("/health", new() { Predicate = c => c.Name == "database" });
// 再加 Schema 版本：還有 Migration 沒跑也回 503（部署死因 3）
app.MapHealthChecks("/health/ready", new() { Predicate = c => c.Tags.Contains("ready") });

// 畫面頁首的環境色條與版本號用：不登入也看得到，但只給環境名稱和版本
var version = Assembly.GetExecutingAssembly()
    .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion.Split('+')[0] ?? "dev";
var startedAt = DateTime.UtcNow;
app.MapGet("/api/system", () => new { environment = app.Environment.EnvironmentName, version, startedAt });

app.MapAuth();
app.MapDeployments();
app.MapUsers();

app.MapFallback("/api/{**path}", () => Results.NotFound());   // 打錯的 API 回 404，不要回首頁
app.MapFallbackToFile("index.html");                         // 其他網址交給前端路由

app.Run();
return 0;
