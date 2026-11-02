# 只打包 CI publish job 產出的 publish/：image 裡就是測過的那份產物（Immutable Artifact），不在這裡重新編譯
FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
COPY publish/ .
ENV ASPNETCORE_HTTP_PORTS=5000
EXPOSE 5000
ENTRYPOINT ["dotnet", "Api.dll"]
