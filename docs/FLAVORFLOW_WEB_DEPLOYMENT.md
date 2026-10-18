# FlavorFlow web deployment

All Flutter builds run in **GitHub Actions**; the VPS only receives the finished web artifact. CircleCI is not used.

## Production target

The app is currently served at `https://app.flavorflow.co.in`. The repository's SaaS VPS setup uses `/opt/flavorflow-saas/web` as Caddy's web root; the GitHub deploy job uses that path by default. The older `tools/ff-webdeploy.sh` is for the separate `flavorflow.duckdns.org` VM and `/opt/flavorflow/web`—do not use it for the app domain.

The Caddy setup script in this repository points both `flavorflow.co.in` and `app.flavorflow.co.in` at the same web root. Confirm the VPS's current Caddy configuration before deploying if that has changed.

## Configure GitHub Actions access

In the repository's **Settings → Secrets and variables → Actions**, add these repository secrets:

- `FLAVORFLOW_DEPLOY_HOST` — SSH host/IP for the production VPS.
- `FLAVORFLOW_DEPLOY_USER` — SSH user.
- `FLAVORFLOW_DEPLOY_SSH_KEY` — private key for that user.
- `FLAVORFLOW_DEPLOY_PORT` — optional; defaults to `22`.

The SSH user must be able to use non-interactive `sudo` for the backup and copy operations under the web root, or be the root user. The workflow uses `ssh-keyscan` to populate a per-run `known_hosts` file. If the actual web root differs from `/opt/flavorflow-saas/web`, set the Actions variable `FLAVORFLOW_DEPLOY_PATH` to the correct absolute path.

Do not put private keys or passwords in chat or in the repository.

## Deploy

After the secrets are configured, pushes to `main` or `arena/b7695262-flavorflow` automatically run the GitHub build. A successful web build is then deployed over SSH; no manual workflow run and no Flutter build on the VPS are needed. If the secrets are absent, the deployment job reports that it skipped.

Deployment backs up the current web root to a sibling `backups` directory, overlays the new Flutter web files without deleting other files such as APK downloads, writes `ff-web-version.txt`, and verifies that the live bundle contains the dispatch batch-code fix.
