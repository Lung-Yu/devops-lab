// 啟動前要有的設定：少一個就列出來（跟 Lab M4 預檢 0 同一件事，這裡是程式裡的版本，給 CI 的單元測試測）
public static class RequiredSettings
{
    public static readonly string[] Keys = ["DB_HOST", "DB_PORT", "DB_NAME", "DB_USER"];

    public static string[] Missing(IConfiguration config) =>
        Keys.Where(key => string.IsNullOrWhiteSpace(config[key])).ToArray();
}
