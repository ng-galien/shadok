FROM eclipse-temurin:21-jre
WORKDIR /app
COPY target/classes /app/classes
COPY target/lib /app/lib
USER 1000:1000
EXPOSE 8080
ENTRYPOINT ["java", "-cp", "/app/classes:/app/lib/*", "example.Application"]
