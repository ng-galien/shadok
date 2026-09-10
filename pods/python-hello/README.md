# Python application example

FastAPI serves plain-text and JSON greetings, health data and OpenAPI documentation. Uvicorn can watch the source directory during development.

From `pods/python-hello`, with Python 3.11+ and venv support:

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

This example owns `shadok.yaml`. From this directory, use `shadok watch --config shadok.yaml --group python-source` after configuring and activating its session.

Follow the [shared session and destination setup](../README.md#before-synchronizing-an-example). Build the image from this directory with `docker build -t python-hello:dev .` and let the platform deploy it. Configure mount `application` with imagePath/mountPath `/app/src`, workingDir `/app`, UID/GID matching the image user, command `python` and args `[-m, uvicorn, "main:app", --host, 0.0.0.0, --port, "8000", --reload, --reload-dir, /app/src]`. The image's PYTHONPATH includes `/app/src`.

Open http://localhost:8000/hello for a local run; use the application's normal route for a cluster run. Stop the local server with Ctrl+C and stop synchronization with `shadok unwatch --config shadok.yaml --group python-source`.
