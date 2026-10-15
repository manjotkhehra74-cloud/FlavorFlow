# Website/support delivery package

This small static website bundle is kept here as a delivery fallback because the user could not access Arena's attachment/temporary preview URLs and GitHub release-asset uploads were unavailable in the agent environment. It is not an Android/Windows application release and does not deploy automatically.

Download **flavorflow-support-release.tar.gz**, not GitHub's whole-repository Source code archives. Upload it to the existing VM home directory, then:

```sh
cd ~
tar -xzf flavorflow-support-release.tar.gz
sudo bash flavorflow-support-release/tools/ff-support-publish.sh "$HOME/flavorflow-support-release/web-landing"
```

The bundle publishes the approved enterprise homepage and support centre with backups. It preserves unrelated Caddy routes and does not modify ERP backend/data. Call support uses the existing business number. Chat/email stay pending until the services are configured and tested. See `docs/SUPPORT_CENTRE.md` for details. The SHA256 companion file identifies the delivered archive; an internal manifest verifies each deployed file.

Prefer release assets/external storage for future generated packages once available; this ~200 KB exception exists only to unblock this requested handoff.
