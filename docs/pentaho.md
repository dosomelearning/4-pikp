# Pentaho Usage

This project runs Pentaho (WebSpoon) as an optional containerized tool.

## Prerequisites
- Docker + Docker Compose available on host.
- Project env file present: `infra/compose/.env`.

## Start Pentaho

From project root:

```bash
./scripts/pentaho-up.sh
```

Notes:
- First run may take time because Docker pulls the image.
- Pentaho service is profile-gated (`tools`) and does not affect default `infra-up` flow.
- `pentaho-up.sh` also normalizes workspace permissions before startup.

## Stop Pentaho

From project root:

```bash
./scripts/pentaho-down.sh
```

This stops and removes the Pentaho container.

## View Pentaho Logs

From project root:

```bash
./scripts/pentaho-logs.sh
```

Tail-only example:

```bash
./scripts/pentaho-logs.sh --tail=100
```

## Access from Host Machine

Open in browser:

- http://localhost:18080

Port is configurable via:

- `PENTAHO_WEB_PORT_HOST` in `infra/compose/.env`

## Workspace Mount (KTR/KJB Files)

Host path:
- `infra/platform/pentaho`

Container path:
- `/workspace/pentaho`

Suggested structure:
- `infra/platform/pentaho/transformations/*.ktr`
- `infra/platform/pentaho/jobs/*.kjb`
- `infra/platform/pentaho/shared/*`

Raw input data mount:
- Host: `raw/`
- Container: `/workspace/raw` (read-only)

Example accidents CSV path in GUI:
- `/workspace/raw/archive/US_Accidents_March23.csv`

## First GUI Steps (Onboarding)

### 1) Create DB Connection

In a transformation (`.ktr`), easiest path:

1. Drag `Table input` step to canvas (temporary helper).
2. Open step and click `New...` next to connection.
3. Configure:
   - Name: `dw_pg`
   - Type: `PostgreSQL`
   - Access: `Native (JDBC)`
   - Host: `postgres`
   - Port: `5432`
   - Database: `dw`
   - User: `dw_user`
   - Password: `dw_pass`
4. Click `Test` and `OK`.
5. Delete temporary `Table input` if not needed.

### 2) Configure CSV Input

1. Add `CSV file input` step.
2. Set filename to source path (for accidents):
   - `/workspace/raw/archive/US_Accidents_March23.csv`
3. Click `Get fields` and preview rows.
4. Save transformation.

## Permissions and Reproducibility

### Why save can fail

- WebSpoon container runs as `uid=999 (tomcat)`.
- Host-mounted workspace files are typically owned by your host user.
- If files are not writable by container user, saving `.ktr/.kjb` fails with permission errors.

### Project fix (permanent workflow)

- Script added:
  - `./scripts/pentaho-fix-perms.sh`
- It runs automatically inside:
  - `./scripts/pentaho-up.sh`
- What it does:
  - `chmod -R a+rwX infra/platform/pentaho`

If needed, you can run it manually:

```bash
./scripts/pentaho-fix-perms.sh
```

## Typical Workflow

1. Start Pentaho: `./scripts/pentaho-up.sh`
2. Open WebSpoon at `http://localhost:18080`
3. Edit/save `.ktr/.kjb` under mounted workspace folders
4. Inspect logs if needed: `./scripts/pentaho-logs.sh --tail=100`
5. Stop when done: `./scripts/pentaho-down.sh`
