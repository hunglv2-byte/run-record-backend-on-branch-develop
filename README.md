# Run docker
```shell
docker compose -f docker-compose.yml up -d --force-recreate
```

## Run record-backend to trace request API using Open telemetry + zipkin

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


# References
- https://github.com/nlinhvu/opentelemetry-order-service-2023