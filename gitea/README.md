# Gitea (Git server for ArgoCD)

Gitea runs on your **Fedora host** in Docker, not inside the Vagrant VMs. The cluster (and ArgoCD) runs in the VMs and reaches Gitea at the host’s IP on the Vagrant network (`192.168.56.1`).

## Start

```bash
docker compose up -d
```

## Access

| Where you are        | URL                        |
|----------------------|----------------------------|
| Browser on Fedora    | http://localhost:3000      |
| Inside a Vagrant VM / ArgoCD | http://192.168.56.1:3000 |

## Let Vagrant VMs reach Gitea (Fedora firewall)

If **http://localhost:3000** works but the VMs cannot reach **http://192.168.56.1:3000**, Fedora’s firewall is blocking it. Allow the Vagrant network only (no need to open port 3000 to the whole internet):

```bash
# Allow the Vagrant private network to reach the host
sudo firewall-cmd --zone=trusted --add-source=192.168.56.0/24 --permanent
sudo firewall-cmd --reload
```

Then from a VM, Gitea should be reachable:

```bash
vagrant ssh k8s-master
curl -sI http://192.168.56.1:3000
```

You should see HTTP headers (e.g. `HTTP/1.1 200 OK` or a redirect). Use the same URL in ArgoCD as the Git repo base.

## Check host IP (if 192.168.56.1 fails)

Confirm the host’s IP on the Vagrant network:

```bash
ip addr show | grep 192.168.56
```

If the host has a different IP (e.g. `192.168.56.2`), use that in ArgoCD and in Gitea’s **Site URL** (Settings → Configuration after first login).

## SSH clone/push (use port 222)

Gitea’s SSH runs on **port 222** on the host (mapped from container port 22). You must use the **`ssh://`** URL form so Git uses port 222. The form `git@host:222/repo` is parsed as path `222/repo` and Git still uses port 22.

**From your machine (localhost):**

```bash
# Add remote (correct – with ssh:// and port 222)
git remote add gitea ssh://git@127.0.0.1:222/farnia/bingo-api-gateway.git

# If the remote already exists with the wrong URL, fix it:
git remote set-url gitea ssh://git@127.0.0.1:222/farnia/bingo-api-gateway.git

# Push
git push -u gitea develop
```

**From a Vagrant VM** (use host IP and same URL form):

```bash
git remote add gitea ssh://git@192.168.56.1:222/farnia/bingo-api-gateway.git
```

Add your SSH public key in Gitea: **Settings → SSH / GPG Keys**.

## First run

1. Open http://localhost:3000 on Fedora and complete the installer.
2. Set **Gitea Base URL** to `http://192.168.56.1:3000/` (or your host IP on the Vagrant network).
3. Create a repo and push your manifests; in ArgoCD use `http://192.168.56.1:3000/<user>/<repo>.git`.
