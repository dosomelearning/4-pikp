# Pentaho Workspace

Mounted into the Pentaho container at:
- `/workspace/pentaho`

Use this folder to store:
- `transformations/*.ktr`
- `jobs/*.kjb`
- shared metadata/config assets in `shared/`

The compose service is profile-gated (`tools`) and can be started via root scripts.

