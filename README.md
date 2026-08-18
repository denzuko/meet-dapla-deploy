# meet-dapla-deploy

Roswell/Consfigurator deploy of [Gathio](https://github.com/lowercasename/gathio)
at `meet.dapla.net`. Gathio is a federated, privacy-respecting event management
application with ActivityPub support and iCal feed export.

## Architecture

```
Cloudflare edge
  └── HAProxy (TLS termination, security headers, iCal/AP buffer sizing)
        └── gathio:3000 (127.0.0.1 only)
              └── gathio-db (internal Podman network, mongo:6)
```

All containers run rootless under the `gathio` service account. Three
AES-256-GCM-encrypted ZFS datasets back the service account home, the MongoDB
data directory, and the event image store. Outbound mail routes through the
panix.com smarthost. Images are mirrored via `oci.dapla.net`.

## Repository Layout

```
meet-dapla-deploy.ros   Thin Roswell entry point
meet-dapla-deploy.asd   Umbrella ASDF system definition
qlfile                   Qlot dependency pins
src/deploy.lisp          Consfigurator properties and DEFHOST
src/docs.lisp            40ants-doc sections
t/e2e.lisp               Post-deploy FiveAM smoke tests
docs.ros                 Documentation generator
Makefile                 build / test / doc / dist / clean
```

## Prerequisites

- Roswell with SBCL
- Qlot (`ros install qlot`)
- Rootless Podman ≥ 4.4 with quadlet support
- Systemd user session with lingering enabled
- HAProxy ≥ 2.6
- ZFS with `storage/users` and `storage/containers` pools
- Panix.com SMTP credentials for outbound mail

## Installation

```sh
ros install qlot
qlot add cl-inix consfigurator fiveam dexador
./meet-dapla-deploy.ros
```

## Runbook

```sh
machinectl shell gathio@ -- systemctl --user status gathio-db gathio
machinectl shell gathio@ -- journalctl --user -u gathio -u gathio-db -f
machinectl shell gathio@ -- systemctl --user restart gathio
machinectl shell gathio@ -- podman auto-update
```

Redeploy by re-running `./meet-dapla-deploy.ros`. Idempotent.

## Playbook

### ZFS replication (rsync.net)

```sh
for ds in gathio-db gathio-events; do
  zfs snapshot storage/containers/${ds}@$(date +%Y%m%d)
  zfs send -w storage/containers/${ds}@$(date +%Y%m%d) | \
    ssh user@rsync.net zfs receive backup/${ds}
done
```

Key files under `/etc/zfs-keys/` must be backed up separately.

## Decommission

```sh
machinectl shell gathio@ -- systemctl --user stop gathio gathio-db
machinectl shell gathio@ -- systemctl --user disable gathio gathio-db
# Destroy datasets only when data loss is acceptable:
zfs destroy -r storage/users/gathio
zfs destroy -r storage/containers/gathio-db
zfs destroy -r storage/containers/gathio-events
```

## License

BSD 3-Clause. See [LICENSE](LICENSE).
