using System.Security.Claims;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using MyApi.Data;
using MyApi.Infrastructure;

namespace MyApi.Endpoints;

public record CreateUserInput(string UserName, string DisplayName, string Role, string Password);
public record UpdateUserInput(string DisplayName, string Role, bool IsActive);

public static class UserEndpoints
{
    public static void MapUsers(this IEndpointRouteBuilder app)
    {
        var g = app.MapGroup("/api/users").RequireAuthorization("AdminOnly");

        // 回傳時不帶 PasswordHash：雜湊值也不該離開後端
        g.MapGet("/", async (AppDbContext db) =>
            await db.Users.AsNoTracking().OrderBy(u => u.Id)
                .Select(u => new { u.Id, u.UserName, u.DisplayName, u.Role, u.IsActive, u.CreatedAt })
                .ToListAsync());

        g.MapPost("/", async (CreateUserInput input, AppDbContext db, ClaimsPrincipal me) =>
        {
            var errors = new Dictionary<string, string[]>();
            if (string.IsNullOrWhiteSpace(input.UserName) || input.UserName.Length > 50) errors["userName"] = ["帳號必填，最多 50 字"];
            if (!Roles.All.Contains(input.Role)) errors["role"] = [$"角色只能是 {string.Join("／", Roles.All)}"];
            if (input.Password is not { Length: >= 8 }) errors["password"] = ["密碼至少 8 碼"];
            if (await db.Users.AnyAsync(u => u.UserName == input.UserName)) errors["userName"] = ["帳號已存在"];
            if (errors.Count > 0) return Results.ValidationProblem(errors, title: "輸入資料有誤");

            var user = new User { UserName = input.UserName.Trim(), DisplayName = input.DisplayName.Trim(), Role = input.Role };
            user.PasswordHash = new PasswordHasher<User>().HashPassword(user, input.Password);
            db.Users.Add(user);
            Audit.Add(db, me, "user.create", $"{user.UserName} ({user.Role})");
            await db.SaveChangesAsync();
            return Results.Created($"/api/users/{user.Id}", new { user.Id, user.UserName, user.DisplayName, user.Role, user.IsActive });
        });

        g.MapPut("/{id:int}", async (int id, UpdateUserInput input, AppDbContext db, ClaimsPrincipal me) =>
        {
            if (!Roles.All.Contains(input.Role))
                return Results.ValidationProblem(new Dictionary<string, string[]> { ["role"] = ["角色不正確"] });
            var user = await db.Users.FindAsync(id);
            if (user is null) return Results.NotFound();
            // 不能把自己降級或停用，避免系統裡沒有管理員
            if (user.UserName == me.Identity!.Name && (input.Role != Roles.Admin || !input.IsActive))
                return Results.Problem(title: "不能降低自己的權限或停用自己", statusCode: 400);

            Audit.Add(db, me, "user.update", $"{user.UserName}: {user.Role}/{user.IsActive} → {input.Role}/{input.IsActive}");
            (user.DisplayName, user.Role, user.IsActive) = (input.DisplayName.Trim(), input.Role, input.IsActive);
            await db.SaveChangesAsync();
            return Results.Ok(new { user.Id, user.UserName, user.DisplayName, user.Role, user.IsActive });
        });

        app.MapGet("/api/audit", async (AppDbContext db) =>
            await db.AuditLogs.AsNoTracking().OrderByDescending(a => a.Id).Take(100).ToListAsync())
            .RequireAuthorization("AdminOnly");
    }
}
