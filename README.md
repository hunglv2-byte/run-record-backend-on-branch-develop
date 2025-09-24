# Run docker
- Run on branch `develop`
```shell
docker compose down && POSTGRES_RECORD_ENV=develop_branch docker compose up -d --force-recreate
```
- Run on branch `auto-insurance-premium-update`
```shell
docker compose down && POSTGRES_RECORD_ENV=auto-insurance-premium-update_branch docker compose up -d --force-recreate
```

## Run record-backend to trace request API using Open telemetry + zipkin

- Run via zipkin
```shell
java \
  -javaagent:/home/dgwo/Documents/otel-probe-agent/build/libs/otel-probe-agent-1.0-SNAPSHOT.jar \
  -Dotel.probe.agent.packages=jp.joinsure.claim,jp.joinsure.policy,jp.joinsure.core.port.adapter.driver.api \
  -javaagent:/home/dgwo/Documents/run-record-backend-on-branch-develop/opentelemetry-javaagent.jar \
  -Dotel.javaagent.debug=true \
  -Dotel.service.name=record-backend \
  -Dotel.traces.exporter=zipkin \
  -Dotel.exporter.zipkin.endpoint=http://localhost:9411/api/v2/spans \
  -Dotel.metrics.exporter=none \
  -Dotel.logs.exporter=none \
  -Dotel.resource.attributes=deployment.environment=dev \
  -Dotel.instrumentation.methods.include.private=true \
  -jar /home/dgwo/Documents/joinsure-record-backend/console/build/libs/console-0.0.1-SNAPSHOT.jar

```

- Run via collector
```shell
java \
  -javaagent:/home/dgwo/Documents/otel-probe-agent/build/libs/otel-probe-agent-1.0-SNAPSHOT.jar \
  -Dotel.probe.agent.packages=jp.joinsure.claim.console,jp.joinsure.policy.console \
  -javaagent:/home/dgwo/Documents/run-record-backend-on-branch-develop/opentelemetry-javaagent.jar \
  -Dotel.javaagent.debug=true \
  -Dotel.service.name=record-backend \
  -Dotel.traces.exporter=otlp \
  -Dotel.exporter.otlp.protocol=grpc \
  -Dotel.exporter.otlp.endpoint=http://localhost:4317 \
  -Dotel.metrics.exporter=none \
  -Dotel.logs.exporter=none \
  -Dotel.resource.attributes=deployment.environment=dev \
  -Dotel.instrumentation.methods.include.private=true \
  -jar /home/dgwo/Documents/joinsure-record-backend/console/build/libs/console-0.0.1-SNAPSHOT.jar
```

# Backup:
`./db_tool.sh backup`

# Restore:
`./db_tool.sh restore <backup_file_name>`
Ex: `./db_tool.sh restore /home/dgwo/Documents/backup_data/20250910141500_backup.sql.gz`

# Run migrate
- Accept permission: `chmod +x migrate_and_codegen.sh`
- Run: `./migrate_and_codegen.sh`

- $ Run test
` ./gradlew :core:test`

# References
- https://github.com/nlinhvu/opentelemetry-order-service-2023