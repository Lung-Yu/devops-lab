using Microsoft.EntityFrameworkCore;

namespace MyApi.Data;

public class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    public DbSet<User> Users => Set<User>();
    public DbSet<Deployment> Deployments => Set<Deployment>();
    public DbSet<AuditLog> AuditLogs => Set<AuditLog>();

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.Entity<User>(e =>
        {
            e.Property(x => x.UserName).HasMaxLength(50);
            e.HasIndex(x => x.UserName).IsUnique();
            e.Property(x => x.DisplayName).HasMaxLength(50);
            e.Property(x => x.Role).HasMaxLength(20);
        });
        b.Entity<Deployment>(e =>
        {
            e.Property(x => x.Customer).HasMaxLength(100);
            e.Property(x => x.Environment).HasMaxLength(20);
            e.Property(x => x.Version).HasMaxLength(30);
            e.Property(x => x.Status).HasMaxLength(20);
            e.Property(x => x.Note).HasMaxLength(500);
            e.Property(x => x.CreatedBy).HasMaxLength(50);
            e.HasIndex(x => x.DeployedAt);
        });
        b.Entity<AuditLog>(e =>
        {
            e.Property(x => x.UserName).HasMaxLength(50);
            e.Property(x => x.Action).HasMaxLength(50);
            e.Property(x => x.Target).HasMaxLength(200);
            e.Property(x => x.TraceId).HasMaxLength(32);
            e.HasIndex(x => x.At);
        });
    }
}
