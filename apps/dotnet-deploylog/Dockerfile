# 第一階段：建置前端（Vue3）——依 package-lock.json 安裝，版本跟大家一樣
FROM node:22-alpine AS web
WORKDIR /web
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY frontend/ .
RUN npm run build

# 第二階段：用 .NET SDK image 編譯後端（自己電腦不用裝 .NET SDK）
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG APP_VERSION=1.0.0
WORKDIR /src
COPY MyApi.csproj packages.lock.json ./
# 依 packages.lock.json 還原；跟 csproj 對不上就失敗，不會偷偷升版
RUN dotnet restore --locked-mode
COPY . .
RUN dotnet publish -c Release -o /app --no-restore -p:InformationalVersion=$APP_VERSION

# 第三階段：只放執行環境、編好的後端和前端靜態檔，image 比較小
FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
COPY --from=build /app .
COPY --from=web /web/dist ./wwwroot
ENV ASPNETCORE_HTTP_PORTS=5000
EXPOSE 5000
ENTRYPOINT ["dotnet", "MyApi.dll"]
