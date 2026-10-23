# FlavorFlow web deployment

All Flutter builds run in **GitHub Actions**; the VPS only receives the finished web artifact. CircleCI is not used.

## Production target

The app is currently served at `https://app.flavorflow.co.in`. Its active Nginx vhost proxies to the FlavorFlow service on `127.0.0.1:4000`; the existing deployment script for that service uses `/opt/flavorflow/web` as its web root. The GitHub deploy job defaults to `/opt/flavorflow/web`. The separate Caddy SaaS setup's `/opt/flavorflow-saas/web` is not the web root used by this Nginx vhost.

## Configure GitHub Actions access

In the repository's **Settings → Secrets and variables → Actions**, add these repository secrets:

- `FLAVORFLOW_DEPLOY_HOST` — SSH host/IP for the production VPS.
- `FLAVORFLOW_DEPLOY_USER` — SSH user.
- `FLAVORFLOW_DEPLOY_SSH_KEY` — private key for that user.
- `FLAVORFLOW_DEPLOY_PORT` — optional; defaults to `22`.

`FLAVORFLOW_DEPLOY_SSH_KEY` must contain the full, unencrypted OpenSSH **private** key (including its `BEGIN` and `END` lines); do not use the `.pub` file, a Windows app-signing key, a PuTTY `.ppk`, or a file path. Install the matching one-line `.pub` key in `~/.ssh/authorized_keys` for the exact `FLAVORFLOW_DEPLOY_USER` account. Keep the private key only in the GitHub Actions secret; never put it in chat or the repository.

The SSH user must own or otherwise have write access to the web root and its sibling `backups` directory; the workflow intentionally does not use `sudo`. For the default paths, run this one-time ownership setup in the VPS SSH terminal (it may prompt for the VPS sudo password): `sudo chown -R "$(id -un):$(id -gn)" /opt/flavorflow/web /opt/flavorflow/backups`. This leaves the server and application data untouched. The workflow uses `ssh-keyscan` to populate a per-run `known_hosts` file. If the actual web root differs from `/opt/flavorflow/web`, set the Actions variable `FLAVORFLOW_DEPLOY_PATH` to the correct absolute path and grant the SSH user write access to it and its sibling `backups` directory.

Do not put private keys or passwords in chat or in the repository.

## Deploy

After the secrets are configured, pushes to `main` or `arena/b7695262-flavorflow` automatically run the GitHub build. The backend deploy and health-check run before the web deploy; after restart, the workflow verifies `/api/drums/plants` responds with an authentication status instead of `404`. A successful web build is then deployed over SSH; no manual workflow run and no Flutter build on the VPS are needed. If the secrets are absent, the deployment job reports that it skipped.

Deployment backs up the current web root to a sibling `backups` directory, overlays the new Flutter web files without deleting other files such as APK downloads, writes `ff-web-version.txt`, and verifies that the live bundle contains the dispatch batch-code fix.
