# Python app deployment with Docker, CI and AWS: config, diagnosis, rollback

[![CI](https://github.com/ZiadEzzaidi/python-docker-deployment/actions/workflows/ci.yml/badge.svg)](https://github.com/ZiadEzzaidi/python-docker-deployment/actions/workflows/ci.yml)

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
docker build -t deployment-lab:2.0 .
docker compose up -d
curl http://127.0.0.1:8080/health
```

On Windows PowerShell, use `copy .env.example .env` for the first step.

## Operate it

| Task | Command |
|---|---|
| Logs | `docker compose logs` |
| Status and exit code | `docker compose ps -a` |
| Release a new version | Change `VERSION` in `app.py` (e.g. `3.0`) → `docker build -t deployment-lab:3.0 .` → set `image: deployment-lab:3.0` in `compose.yaml` → `docker compose up -d --force-recreate` |
| Roll back | Set `image:` back to the previous tag (e.g. `deployment-lab:2.0`) → `docker compose up -d --force-recreate` (no rebuild: the previous image is still stored locally) |
| Stop | `docker compose down` |

## Incident diagnosed

- **Symptom:** the container was running, but every request to `127.0.0.1:8080` was dropped.
- **Evidence:** the startup log said `listening on 127.0.0.1:8000`.
- **Cause:** the app binds to `127.0.0.1` by default. Inside a container, that is the container's own loopback, so traffic forwarded from the host, which arrives on the container's network interface, never reaches the app.
- **Fix:** `BIND_HOST=0.0.0.0` in `.env`. The app now listens on all interfaces inside the container, while the host side stays restricted to localhost through the port mapping.

## Failure handling verified

- **Missing configuration:** with `APP_MESSAGE` empty, the app refuses to start, exits with code 1 and logs `STARTUP ERROR: APP_MESSAGE must be set and non-empty`. Visible with `docker compose ps -a` and `docker compose logs`. Restoring the value and recreating the container brings the service back.
- **Release and rollback:** version 2.0 was built and deployed, then rolled back to 1.0 without rebuilding; `/health` confirmed the running version each time.

## Continuous integration

Every push to `main` and every pull request runs [`.github/workflows/ci.yml`](.github/workflows/ci.yml) on a fresh GitHub runner:

1. Build the image.
2. Start a container with runtime config.
3. Run [`tests/smoke_test.py`](tests/smoke_test.py): `/health` returns 200 with the version of the code in that commit, `/` returns the message supplied at runtime, unknown paths return 404.
4. Start the app without `APP_MESSAGE` and require exit code 1, so the safety check is tested too.
5. If anything fails, print the container logs before the runner is discarded.

The same smoke test runs against a local deployment:

```bash
python tests/smoke_test.py http://127.0.0.1:8080 "Deployment works"
```

**Breaking change blocked:** to test the pipeline, a pull request deliberately renamed the variable read by the startup check (`APP_MESSAGE` → `APP_MSG`). CI went red: the container logs showed the startup error even though CI supplied `APP_MESSAGE`, and the diff showed why. The fix was to reject the change rather than rename the variable in CI, because `APP_MESSAGE` is the documented configuration every existing `.env` relies on. `main` never received the bug ([PR #1](https://github.com/ZiadEzzaidi/python-docker-deployment/pull/1)).

## Deployment on AWS

```
git tag vX.Y ──▶ CI: test, then publish ghcr.io/ziadezzaidi/python-docker-deployment:X.Y
                                   │ pulled by
                                   ▼
Browser ──port 80──▶ [Security group] ──▶ EC2 t3.micro (Amazon Linux 2023, Docker)
                     one allowed IP only        config in /opt/app/.env on the server
```

- **Releases are tags.** Pushing `v1.0` runs the tests, checks the tag matches `VERSION` in `app.py`, then publishes image `1.0`. A published version never changes, which is what makes rollback trustworthy.
- **Firewall:** only port 80, only from one allowed IP. No SSH port is open.
- **Admin access through AWS Systems Manager:** the server's role has a single policy, `AmazonSSMManagedInstanceCore`. IMDSv2 is required.
- **Config stays on the server** (`/opt/app/.env`), never in the public image.

Scripts in [`deploy/aws/`](deploy/aws/) (PowerShell, AWS CLI v2 signed in):

```powershell
./deploy/aws/create.ps1  -AwsProfile <profile>                # role, firewall, server; waits for /health
./deploy/aws/deploy.ps1  -AwsProfile <profile> -Version 2.0   # update through Systems Manager
./deploy/aws/deploy.ps1  -AwsProfile <profile> -Version 1.0   # rollback
./deploy/aws/destroy.ps1 -AwsProfile <profile>                # delete everything it created
```

### Evidence (deployed on 6 October 2026, then torn down)

![App answering from EC2](docs/aws-live-app.jpg)

The same smoke test as CI, run against the server's public address:

```
ok: /health returns 200
ok: /health reports status ok
ok: /health reports version 1.0, the code in this commit
ok: / returns 200
ok: / returns the message supplied at runtime
ok: unknown paths return 404
All smoke tests passed
```

Update and rollback through Systems Manager, no SSH:

```
| 2026-10-06T18:12:29 | Diagnose from inside | Success |
| 2026-10-06T18:06:55 | Rollback to 1.0      | Success |
| 2026-10-06T17:59:39 | Deploy 2.0           | Success |
```

The rollback downloaded nothing, because the 1.0 image was still on the server:

```
Status: Image is up to date for ghcr.io/ziadezzaidi/python-docker-deployment:1.0
/health -> {"status":"ok","version":"1.0"}
```

### Incident: site unreachable

- **Symptom:** the browser hung, then gave up. A timeout, not an immediate "connection refused".
- **Evidence, collected from inside the server through Systems Manager:** the container was `Up` and `curl localhost/health` answered `ok`. App and server were healthy, so the traffic was being dropped before reaching them.
- **Cause:** the security group had no inbound rule left (`"InboundRules": []`).
- **Fix:** restore the port 80 rule for the allowed IP; the site answered again.
- **Rule of thumb:** a timeout means something filters traffic silently; "connection refused" means the machine was reached but nothing is listening.

## Key ideas

- **Image vs container:** the image is the frozen package; the container is a running instance of it. Several releases can sit side by side as tagged images.
- **Two ports:** `8000` is where the app listens inside the container; `8080` is where you reach it on the host. The mapping `127.0.0.1:8080:8000` connects them and keeps the service off the network.
- **Config flow:** `.env` → `env_file` in `compose.yaml` → container environment → `os.environ` in `app.py`. Environment variables are read when the container starts, so a config change needs a recreated container.

## Scope

Docker packaging, CI and versioned releases on GitHub Actions, and deployment to a single EC2 server with update and rollback. A production setup would add HTTPS, a domain name, monitoring and alerting.
