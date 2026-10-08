# Rapport technique — API Flask / PostgreSQL

## 1. Packages GHCR

Package de l'API : https://github.com/vitalikevin/tp_devsecops/pkgs/container/tp_devsecops%2Fapi

```bash
docker pull ghcr.io/vitalikevin/tp_devsecops/api:1.0.0
```

## 2. Avant / Après

| Critère | Avant | Après |
|---|---|---|
| Taille (compressée) | 54,4 Mo | 37,6 Mo |
| Utilisateur | root | 65532 (nonroot) |
| Shell | oui | non |
| CVE Trivy | 185 (47 HIGH) | 0 |
| Efficience Dive | 97,4 % | 99,8 % |

## 3. Images de base

Image retenue pour l'API : **Chainguard Python**. Elle n'a ni shell ni gestionnaire de paquets, elle tourne en non-root par défaut, et elle a 0 CVE. Le build se fait dans `latest-dev`, qui contient pip, et l'exécution dans `latest`.

Pour garantir l'immuabilité, chaque `FROM` est épinglé par digest SHA256, et toutes les dépendances Python avec `==`.

## 4. Healthchecks sans shell

Sans shell dans l'image, un healthcheck en `CMD-SHELL` échoue. Les deux sondes sont donc en forme exec `["CMD", ...]`.

**API :** on passe par le Python de l'image et `urllib` (bibliothèque standard). La commande renvoie 0 si `/health` répond 200, 1 sinon.

```yaml
test: ["CMD", "/usr/bin/python", "-c", "import sys, urllib.request; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:5000/health', timeout=3).status == 200 else 1)"]
```

**PostgreSQL :** image `cgr.dev/chainguard/postgres` épinglée par digest, sonde avec `pg_isready`, qui est fourni dans l'image.

```yaml
test: ["CMD", "pg_isready", "-U", "${DB_USER}", "-d", "${DB_NAME}"]
```

L'API attend la base avec `depends_on: condition: service_healthy`.

L'image Postgres contient `bash` pour son script d'entrée. Le processus `postgres` tourne en UID 70, pas en root.

## 5. Remédiations

**Flake8 :** 0 violation avec le `.flake8` fourni ; `app.py` et `test_app.py` d'origine n'ont rien eu à corriger.

**Dépendances :**

| Paquet | Avant | Après | Raison |
|---|---|---|---|
| Flask | 2.3.2 | 3.1.3 | CVE-2026-27205 ; compatibilité avec Python 3.14 |
| Werkzeug | 2.3.3 | 3.1.9 | CVE-2024-34069 (HIGH) et 7 MEDIUM |
| pytest | 7.4.0 | 9.1.1 | CVE-2025-71176 |
| psycopg2-binary | non épinglé | 2.9.13 | reproductibilité |

Le venv est créé sans pip (`--without-pip`). Sinon, pip serait copié dans l'image finale, avec ses propres CVE HIGH.

## 6. Sécurisation CI/CD

Workflow `.github/workflows/ci.yaml` : lint-python, lint-docker → build + Dive → trivy, integration → release.

**Permissions :** `permissions: {}` au niveau global. Chaque job demande `contents: read`, et seul `release` a `packages: write`. La connexion à GHCR se fait avec le `GITHUB_TOKEN`.

**Pinning :** toutes les actions sont épinglées par SHA de commit, la version étant notée en commentaire. Un tag peut être déplacé, un SHA non. L'image Dive est épinglée par digest.

L'image est construite une seule fois, puis passée aux autres jobs en artefact. On publie donc celle qui a été scannée et testée.

**SemVer :** la release ne part que sur un tag `vX.Y.Z`, et seulement si tous les jobs sont verts. `docker/metadata-action` génère les tags `X.Y.Z`, `X.Y` et `X`.

## 7. Preuves d'exécution

Contrôles de la CI rejoués en local.

**Flake8 :**
```
$ flake8 .
$ echo $?
0
```

**Hadolint :**
```
$ hadolint Dockerfile
$ echo $?
0
```

**Dive :**
```
  efficiency: 99.7592 %
  PASS: lowestEfficiency
Result:PASS [Total:3] [Passed:1] [Failed:0] [Warn:0] [Skipped:2]
```

**Trivy :**
```
/image.tar (wolfi 20230201)   wolfi        0
requirements.txt              pip          0
```

**Compose :**
```
$ docker compose up -d --no-build --wait --wait-timeout 120
 Container devsecops-tp1-db-1  Healthy
 Container devsecops-tp1-api-python-1  Healthy
$ curl -f http://localhost:5000/health
{"status":"ok"}
$ curl -f http://localhost:5000/dbtest
{"db_connection":"successful"}
```

**Pytest :**
```
2 passed, 1 deselected
```

**Publication GHCR :**
```
$ docker pull ghcr.io/vitalikevin/tp_devsecops/api:1.0.0
Digest: sha256:4624119c4e7b55989d1cc6789e96f223d89359223d2b24ac5fe6e87448fc6bf3
Status: Image is up to date for ghcr.io/vitalikevin/tp_devsecops/api:1.0.0
```
