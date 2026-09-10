FROM eclipse-temurin:21-jre AS live
WORKDIR /app
COPY target/classes /app/classes
COPY target/lib /app/lib
USER 1000:1000
EXPOSE 8080
ENTRYPOINT ["java", "-cp", "/app/classes:/app/lib/*", "example.Application"]

# Production baseline excludes the development restart mechanism entirely.
FROM live AS production
USER root
RUN rm /app/lib/spring-boot-devtools-*.jar
USER 1000:1000
