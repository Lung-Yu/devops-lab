using System.Security.Claims;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using MyApi.Data;
using MyApi.Infrastructure;

namespace MyApi.Endpoints;

public record LoginRequest(string UserName, string Password);

public static class AuthEndpoints
{
    public static void MapAuth(this IEndpointRouteBuilder app)
    {
        var g = app.MapGroup("/api/auth");

        g.MapPost("/login", async (LoginRequest req, AppDbContext db, HttpContext http, ILogger<LoginRequest> log) =>
        {
            var user = await db.Users.SingleOrDefaultAsync(u => u.UserName == req.UserName);
            var ok = user is { IsActive: true } &&
                     new PasswordHasher<User>().VerifyHashedPassword(user, user.PasswordHash, req.Password)
                        != PasswordVerificationResult.Failed;
            if (!ok)
            {
                // 登入失敗要留紀錄（資安稽核要看），但絕不記密碼
                log.LogWarning("登入失敗 {UserName}", req.UserName);
                Audit.Add(db, new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.Name, req.UserName)], "none")), "login.failed");
                await db.SaveChangesAsync();
                // 帳號不存在和密碼錯誤回一樣的訊息，避免被用來猜帳號
                return Results.Problem(title: "帳號或密碼錯誤", statusCode: 401);
            }

            var principal = new ClaimsPrincipal(new ClaimsIdentity(
                [
                    new Claim(ClaimTypes.NameIdentifier, user!.Id.ToString()),
                    new Claim(ClaimTypes.Name, user.UserName),
                    new Claim(ClaimTypes.Role, user.Role),
                ], CookieAuthenticationDefaults.AuthenticationScheme));
            await http.SignInAsync(CookieAuthenticationDefaults.AuthenticationScheme, principal);
            Audit.Add(db, principal, "login");
            await db.SaveChangesAsync();
            log.LogInformation("登入成功 {UserName} {Role}", user.UserName, user.Role);
            return Results.Ok(new { user.UserName, user.DisplayName, user.Role });
        });

        g.MapPost("/logout", async (HttpContext http) =>
        {
            await http.SignOutAsync(CookieAuthenticationDefaults.AuthenticationScheme);
            return Results.NoContent();
        });

        g.MapGet("/me", async (ClaimsPrincipal me, AppDbContext db) =>
        {
            var user = await db.Users.FindAsync(int.Parse(me.FindFirstValue(ClaimTypes.NameIdentifier)!));
            return user is null ? Results.Unauthorized() : Results.Ok(new { user.UserName, user.DisplayName, user.Role });
        }).RequireAuthorization();
    }
}
