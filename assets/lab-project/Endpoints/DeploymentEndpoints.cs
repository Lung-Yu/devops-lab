using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using MyApi.Data;
using MyApi.Infrastructure;

namespace MyApi.Endpoints;

public record DeploymentInput(string Customer, string Environment, string Version, string Status, string? Note, DateTime DeployedAt);

public static class DeploymentEndpoints
{
    public static void MapDeployments(this IEndpointRouteBuilder app)
    {
        // 預設：登入就能看；改資料要 CanEdit，刪除要 AdminOnly——權限在後端擋，前端藏按鈕只是方便
        var g = app.MapGroup("/api/deployments").RequireAuthorization();

        g.MapGet("/", async (string? environment, string? status, AppDbContext db) =>
        {
            var q = db.Deployments.AsNoTracking();
            if (!string.IsNullOrEmpty(environment)) q = q.Where(d => d.Environment == environment);
            if (!string.IsNullOrEmpty(status)) q = q.Where(d => d.Status == status);
            return await q.OrderByDescending(d => d.DeployedAt).Take(200).ToListAsync();
        });

        g.MapPost("/", async (DeploymentInput input, AppDbContext db, ClaimsPrincipal me) =>
        {
            if (Validate(input) is { } error) return error;
            var d = new Deployment
            {
                Customer = input.Customer.Trim(), Environment = input.Environment, Version = input.Version.Trim(),
                Status = input.Status, Note = input.Note, DeployedAt = input.DeployedAt.ToUniversalTime(),
                CreatedBy = me.Identity!.Name!,
            };
            db.Deployments.Add(d);
            Audit.Add(db, me, "deployment.create", $"{d.Customer} {d.Environment} {d.Version}");
            await db.SaveChangesAsync();
            return Results.Created($"/api/deployments/{d.Id}", d);
        }).RequireAuthorization("CanEdit");

        g.MapPut("/{id:int}", async (int id, DeploymentInput input, AppDbContext db, ClaimsPrincipal me) =>
        {
            if (Validate(input) is { } error) return error;
            var d = await db.Deployments.FindAsync(id);
            if (d is null) return Results.NotFound();
            Audit.Add(db, me, "deployment.update", $"#{id} {d.Status} → {input.Status}");
            (d.Customer, d.Environment, d.Version, d.Status, d.Note, d.DeployedAt, d.UpdatedAt) =
                (input.Customer.Trim(), input.Environment, input.Version.Trim(), input.Status, input.Note,
                 input.DeployedAt.ToUniversalTime(), DateTime.UtcNow);
            await db.SaveChangesAsync();
            return Results.Ok(d);
        }).RequireAuthorization("CanEdit");

        g.MapDelete("/{id:int}", async (int id, AppDbContext db, ClaimsPrincipal me) =>
        {
            var d = await db.Deployments.FindAsync(id);
            if (d is null) return Results.NotFound();
            db.Deployments.Remove(d);
            Audit.Add(db, me, "deployment.delete", $"#{id} {d.Customer} {d.Version}");
            await db.SaveChangesAsync();
            return Results.NoContent();
        }).RequireAuthorization("AdminOnly");
    }

    // 輸入驗證放後端：前端的檢查可以被繞過（直接打 API）
    static IResult? Validate(DeploymentInput i)
    {
        var errors = new Dictionary<string, string[]>();
        if (string.IsNullOrWhiteSpace(i.Customer) || i.Customer.Length > 100) errors["customer"] = ["客戶名稱必填，最多 100 字"];
        if (string.IsNullOrWhiteSpace(i.Version) || i.Version.Length > 30) errors["version"] = ["版本必填，最多 30 字"];
        if (string.IsNullOrWhiteSpace(i.Environment) || i.Environment.Length > 20) errors["environment"] = ["環境必填"];
        if (!DeploymentStatus.All.Contains(i.Status)) errors["status"] = [$"狀態只能是 {string.Join("／", DeploymentStatus.All)}"];
        if (i.Note?.Length > 500) errors["note"] = ["備註最多 500 字"];
        return errors.Count == 0 ? null : Results.ValidationProblem(errors, title: "輸入資料有誤");
    }
}
