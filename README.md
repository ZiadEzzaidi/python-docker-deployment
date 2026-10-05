# Python app deployment with Docker: config, diagnosis, rollback

Case study: packaging an existing Python web service so anyone can start it the same way, configure it without touching the code, see why it failed, and roll back a bad release.

## The problem

A small Python HTTP service (`app.py`, standard library only) ran with `python app.py` on one machine. The goal was to make it:

- start consistently on any machine with Docker
- take its configuration at runtime, not from the code
- show clearly why it failed
- go back to the previous version after an update, without rebuilding it

## What was built

| File | Role |
|---|---|
| `Dockerfile` | Packages the app into an image (`python:3.12-slim`, exec-form `CMD` so `docker stop` reaches the app directly) |
| `compose.yaml` | Runs the image, publishes the port on localhost only (`127.0.0.1:8080` → `8000`), loads config from `.env` |
| `.env.example` | Documents the configuration the app needs |
| `.gitignore`, `.dockerignore` | Keep the real `.env` out of git and out of the image build context |

## Run it

```bash
cp .env.example .env              # then set APP_MESSAGE, e.g. APP_MESSAGE=Deployment works
docker build -t deployment-lab:1.0 .
docker compose up -d
curl http://127.0.0.1:8080/health
```

On Windows PowerShell, use `copy .env.example .env` for the first step.

## Operate it

| Task | Command |
|---|---|
| Logs | `docker compose logs` |
| Status and exit code | `docker compose ps -a` |
| Release a new version | Change `VERSION` in `app.py` → `docker build -t deployment-lab:2.0 .` → set `image: deployment-lab:2.0` in `compose.yaml` → `docker compose up -d --force-recreate` |
| Roll back | Set `image: deployment-lab:1.0` in `compose.yaml` → `docker compose up -d --force-recreate` (no rebuild: the 1.0 image is still stored locally) |
| Stop | `docker compose down` |

## Incident diagnosed

- **Symptom:** the container was running, but every request to `127.0.0.1:8080` was dropped.
- **Evidence:** the startup log said `listening on 127.0.0.1:8000`.
- **Cause:** the app binds to `127.0.0.1` by default. Inside a container, that is the container's own loopback, so traffic forwarded from the host, which arrives on the container's network interface, never reaches the app.
- **Fix:** `BIND_HOST=0.0.0.0` in `.env`. The app now listens on all interfaces inside the container, while the host side stays restricted to localhost through the port mapping.

## Failure handling verified

- **Missing configuration:** with `APP_MESSAGE` empty, the app refuses to start, exits with code 1 and logs `STARTUP ERROR: APP_MESSAGE must be set and non-empty`. Visible with `docker compose ps -a` and `docker compose logs`. Restoring the value and recreating the container brings the service back.
- **Release and rollback:** version 2.0 was built and deployed, then rolled back to 1.0 without rebuilding; `/health` confirmed the running version each time.

## Key ideas

- **Image vs container:** the image is the frozen package; the container is a running instance of it. Several releases can sit side by side as tagged images.
- **Two ports:** `8000` is where the app listens inside the container; `8080` is where you reach it on the host. The mapping `127.0.0.1:8080:8000` connects them and keeps the service off the network.
- **Config flow:** `.env` → `env_file` in `compose.yaml` → container environment → `os.environ` in `app.py`. Environment variables are read when the container starts, so a config change needs a recreated container.

## Scope

Local Docker setup. CI (GitHub Actions) and cloud deployment are the next steps.
