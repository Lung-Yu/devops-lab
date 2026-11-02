namespace MyApi.Data;

// 三種角色：Viewer 只能看、Engineer 能登錄／修改部署紀錄、Admin 另外能刪除與管理帳號
public static class Roles
{
    public const string Admin = "Admin";
    public const string Engineer = "Engineer";
    public const string Viewer = "Viewer";
    public static readonly string[] All = [Admin, Engineer, Viewer];
}

public class User
{
    public int Id { get; set; }
    public required string UserName { get; set; }
    public required string DisplayName { get; set; }
    public string PasswordHash { get; set; } = "";
    public required string Role { get; set; }
    public bool IsActive { get; set; } = true;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

// 一筆部署紀錄：哪個客戶環境、裝了哪個版本、結果如何
public class Deployment
{
    public int Id { get; set; }
    public required string Customer { get; set; }
    public required string Environment { get; set; }
    public required string Version { get; set; }
    public required string Status { get; set; }
    public string? Note { get; set; }
    public DateTime DeployedAt { get; set; } = DateTime.UtcNow;
    public required string CreatedBy { get; set; }
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}

public static class DeploymentStatus
{
    public static readonly string[] All = ["Planned", "Deploying", "Succeeded", "Failed", "RolledBack"];
}

// 稽核紀錄：誰、什麼時候、做了什麼（第二個 Migration 才加進來，Module 6 示範用）
public class AuditLog
{
    public long Id { get; set; }
    public DateTime At { get; set; } = DateTime.UtcNow;
    public required string UserName { get; set; }
    public required string Action { get; set; }
    public string? Target { get; set; }
    public string? TraceId { get; set; }
}
