# Python application example

FastAPI serves plain-text and JSON greetings, health data and OpenAPI documentation. Uvicorn can watch the source directory during development.

From this directory:

```sh
./start.sh install
./start.sh test
./start.sh dev
```

The helper uses a local virtual environment and the pinned dependencies in `requirements.txt`. `./start.sh help` lists Docker and Kubernetes helpers. Review the selected kubectl context before using any helper that applies manifests.

Default endpoints on port 8000:

- `/hello`: plain-text greeting.
- `/hello/json`: structured greeting with application and Pod metadata.
- `/health`: application health and uptime.
- `/docs`: Swagger UI.
- `/openapi.json`: API schema.

Use `shadok learn` to configure a source watch group, a personal gateway destination and a generic session. The session start command must run uvicorn with reload enabled against the mounted source path. Tests use `pytest` under `tests/`; the optional `test-endpoints.sh` checks a running local server.
