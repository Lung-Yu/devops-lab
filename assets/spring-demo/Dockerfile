# 第一階段：用 Maven image 編譯（自己電腦不用裝 JDK、Maven）
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /src
COPY pom.xml .
# 先只下載套件：pom.xml 沒改就用快取，改程式重建時不用重抓
RUN mvn -B --no-transfer-progress dependency:go-offline
COPY src ./src
RUN mvn -B --no-transfer-progress -DskipTests package

# 第二階段：只放 JRE 和打包好的 jar
FROM eclipse-temurin:17-jre
WORKDIR /app
COPY --from=build /src/target/deploylog-spring-1.0.0.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
