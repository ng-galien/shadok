FROM eclipse-temurin:21-jre AS builder
WORKDIR /builder
COPY target/spring-hello-0.1.0.jar application.jar
RUN java -Djarmode=tools -jar application.jar extract --layers --destination extracted

FROM eclipse-temurin:21-jre AS production
WORKDIR /app
COPY --from=builder /builder/extracted/dependencies/ ./
COPY --from=builder /builder/extracted/spring-boot-loader/ ./
COPY --from=builder /builder/extracted/snapshot-dependencies/ ./
COPY --from=builder /builder/extracted/application/ ./
USER 1000:1000
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/application.jar"]
