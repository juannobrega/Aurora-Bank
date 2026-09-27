# Build em duas etapas: a imagem final não carrega Maven nem código-fonte.

FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /build

# As dependências mudam bem menos que o código: baixar primeiro aproveita
# o cache de camadas entre builds.
COPY pom.xml .
RUN mvn -q dependency:go-offline -B

COPY src ./src
RUN mvn -q clean package -DskipTests -B

# ---------------------------------------------------------------- runtime

FROM eclipse-temurin:21-jre-alpine
WORKDIR /app

# Usuário sem privilégios: nada aqui precisa de root.
RUN addgroup -S aurora && adduser -S aurora -G aurora
USER aurora

COPY --from=build --chown=aurora:aurora /build/target/*.jar app.jar

EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=3s --start-period=40s --retries=5 \
  CMD wget -qO- http://localhost:8080/actuator/health >/dev/null 2>&1 || exit 1

ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "-jar", "app.jar"]
