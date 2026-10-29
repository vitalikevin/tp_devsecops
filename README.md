# Rapport technique — API Flask / PostgreSQL

## 1. Packages GHCR

Package de l'API : https://github.com/vitalikevin/tp_devsecops/pkgs/container/tp_devsecops%2Fapi

```bash
docker pull ghcr.io/vitalikevin/tp_devsecops/api:2.0.1
docker pull ghcr.io/vitalikevin/tp_devsecops/api:2.0
docker pull ghcr.io/vitalikevin/tp_devsecops/api:2
```

## 2. Avant / Après

| Critère | Avant | Après |
|---|---|---|
| Taille (compressée) | 54,4 Mo | 38,9 Mo |
| Utilisateur | root | 65532 (nonroot) |
| Shell | oui | non |
| CVE Trivy | 185 (47 HIGH) | 0 |
| Efficience Dive | 97,4 % | 99,8 % |

## 3. Images de base

Image retenue pour l'API : **Chainguard Python**. Elle n'a ni shell ni gestionnaire de paquets, elle tourne en non-root par défaut, et Trivy n'y relève aucune CVE. Le build se fait dans `latest-dev`, qui contient pip, et l'exécution dans `latest`.

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

Workflow `.github/workflows/ci.yaml` : lint-python, lint-docker → build + Dive → sbom + grype, trivy, integration (en parallèle) → release → sign → verify.

**Permissions :** `permissions: {}` au niveau global. Chaque job demande `contents: read`. Seuls `release` et `sign` ont `packages: write`, et seul `sign` a `id-token: write` pour la signature keyless. La connexion à GHCR se fait avec le `GITHUB_TOKEN`.

**Pinning :** toutes les actions sont épinglées par SHA de commit, la version étant notée en commentaire. Un tag peut être déplacé, un SHA non. Les images Dive, Syft et Grype sont épinglées par digest.

L'image amd64 (cible bake `api-ci`) est construite une seule fois, puis passée aux autres jobs en artefact : Dive, SBOM, Trivy, Grype et intégration portent sur la même image. La release la reconstruit en amd64 + arm64 à partir des mêmes sources et des mêmes `FROM` épinglés. C'est le digest de cet index multi-arch qui est signé puis vérifié.

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
  efficiency: 99.7550 %
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
$ docker pull ghcr.io/vitalikevin/tp_devsecops/api:2.0.1
Digest: sha256:abaf6c106c2ef00f7bcb8a985d8742a3eb645de73b4d570bcb8c245f000a048f
Status: Downloaded newer image for ghcr.io/vitalikevin/tp_devsecops/api:2.0.1
```

## 8. Preuves d'industrialisation BuildKit

### Cache pip persistant

Mesure sur un builder BuildKit neuf, donc avec un cache vide, puis après ajout d'une dépendance (`six==1.17.0`) dans `requirements.txt` :

| Build | Durée totale | Étape `pip install` | Paquets téléchargés |
|---|---|---|---|
| Initial, à froid | 38,9 s | 4,1 s | 13 |
| Après ajout d'une dépendance | 7,4 s | 2,5 s | 1 (`six`) |

```
$ docker buildx create --name tp2-bench --driver docker-container
$ time docker buildx build --builder tp2-bench --secret id=pip_config,src=secrets/pip.conf --load -t tp2/api:bench .
real    0m38.945s
$ echo "six==1.17.0" >> requirements.txt
$ time docker buildx build --builder tp2-bench --secret id=pip_config,src=secrets/pip.conf --load -t tp2/api:bench .
#14 0.884 Using cached flask-3.1.3-py3-none-any.whl (103 kB)
#14 0.888 Using cached psycopg2_binary-2.9.13-cp315-cp315-manylinux2014_x86_64.manylinux_2_17_x86_64.whl (4.3 MB)
#14 0.957 Downloading six-1.17.0-py2.py3-none-any.whl (11 kB)
real    0m7.379s
```

La couche `pip install` est reconstruite, mais pip ne retélécharge que `six`. Le cache reste dans le montage BuildKit, pas dans l'image. En CI, il est exporté vers le cache GitHub Actions (`type=gha`, `mode=max` dans `docker-bake.hcl`).

### Secret de build

Test avec un faux jeton (`tp2-faux-jeton-7f3c9a`) dans `secrets/pip.conf`. Ce fichier est ignoré par Git et exclu du contexte de build par `.dockerignore`.

```
$ docker history --no-trunc tp2/api:bench | grep -c tp2-faux-jeton
0
$ docker export $(docker create tp2/api:bench) | grep -ac tp2-faux-jeton
0
$ docker export $(docker create tp2/api:bench) | tar -t | grep -cE 'pip\.conf|\.cache/pip'
0
$ trivy image --scanners secret --exit-code 1 tp2/api:bench
$ echo $?
0
```

En CI, le job `build` affiche `docker history --no-trunc`, et le job `trivy` scanne aussi les secrets de l'image (scanner `secret` actif par défaut, `exit-code: 1`).

### Manifeste multi-arch

```
$ docker buildx imagetools inspect ghcr.io/vitalikevin/tp_devsecops/api:2.0.1
Name:      ghcr.io/vitalikevin/tp_devsecops/api:2.0.1
MediaType: application/vnd.oci.image.index.v1+json
Digest:    sha256:abaf6c106c2ef00f7bcb8a985d8742a3eb645de73b4d570bcb8c245f000a048f

Manifests:
  Name:        ghcr.io/vitalikevin/tp_devsecops/api:2.0.1@sha256:516f63ac3cd1c41be20cd4dfe7bf768b071a99b0be9508f43466a222e7979e64
  Platform:    linux/amd64

  Name:        ghcr.io/vitalikevin/tp_devsecops/api:2.0.1@sha256:9ac99a62cb2130f63d7ceec5ab1c4f09a08575504d3628904d5a3418fb919239
  Platform:    linux/arm64
```
Les deux autres entrées de l'index (`unknown/unknown`) sont les attestations de provenance ajoutées par BuildKit.

## 9. Analyse de Traçabilité & Gouvernance VEX

### SBOM

Le job `sbom` génère l'inventaire avec Syft, par analyse statique de l'image exportée (`docker-archive:image.tar`), sans lancer le conteneur. Il le produit dans deux formats : CycloneDX JSON (`sbom.cdx.json`, standard OWASP) et SPDX JSON (`sbom.spdx.json`, norme ISO/IEC 5962). Les deux fichiers sont publiés en artefact CI `sbom` et versionnés à la racine du dépôt.

**Nombre de composants :**
```
$ jq '.packages | length' sbom.spdx.json
44
$ jq '[.components[] | select(.type != "file")] | length' sbom.cdx.json
44
$ jq -r '.components | group_by(.type) | map("\(.[0].type): \(length)")[]' sbom.cdx.json
file: 1876
library: 43
operating-system: 1
```

Les deux formats recensent les mêmes 44 composants : 43 paquets (APK Wolfi et Python) et le système d'exploitation. Les 1876 autres entrées CycloneDX sont des fichiers, avec leur empreinte.

**PURL des dépendances Python :**
```
$ jq -r '.components[] | select(.purl) | .purl' sbom.cdx.json | grep pypi
pkg:pypi/blinker@1.9.0
pkg:pypi/click@8.5.0
pkg:pypi/flask@3.1.3
pkg:pypi/iniconfig@2.3.1
pkg:pypi/itsdangerous@2.2.0
pkg:pypi/jinja2@3.1.6
pkg:pypi/markupsafe@3.0.4
pkg:pypi/packaging@26.3
pkg:pypi/pluggy@1.7.0
pkg:pypi/psycopg2-binary@2.9.13
pkg:pypi/pygments@2.21.0
pkg:pypi/pytest@9.1.1
pkg:pypi/werkzeug@3.1.9
```

**Licences détectées :**
```
$ jq -r '[.components[].licenses[]? | .license.id // .license.name // .expression] | unique[]' sbom.cdx.json
Apache-2.0
Apache-2.0 OR BSD-2-Clause
BSD-2-Clause
BSD-2-Clause AND GPL-2.0-only
BSD-3-Clause
GPL-3.0-or-later
GPL-3.0-or-later AND GPL-2.0-or-later AND GPL-2.0-only AND GPL-1.0-only AND LGPL-2.1-or-later AND BSD-1-Clause AND BSD-2-Clause AND BSD-3-Clause AND BSD-4-Clause-UC AND MIT AND CC-PDDC
GPL-3.0-or-later WITH GCC-exception-3.1
LGPL with exceptions
LGPL-2.1-or-later
MIT
MPL-2.0 AND MIT
PSF-2.0
blessing
```

### Scan Grype sur le SBOM

Le job `grype` ne rescanne pas l'image : il analyse `sbom.cdx.json` (`grype sbom:sbom.cdx.json`). Le seuil est versionné dans `.grype.yaml` : `fail-on-severity: high` et `only-fixed: true`. Le job échoue donc sur toute faille haute ou critique qui a un correctif. Le job `release` dépend de `grype`.

```
$ grype sbom:sbom.cdx.json
NAME         INSTALLED              TYPE  VULNERABILITY    SEVERITY  EPSS         RISK
python-3.15  3.15.0_git20261017-r4  apk   CVE-2026-114583  Medium    0.2% (13th)  0.1   (suppressed)
$ echo $?
0
```

### Déclaration VEX

`security.vex.json` (OpenVEX v0.2.0) qualifie la seule faille résiduelle du SBOM :

| CVE | Produit | Statut | Justification |
|---|---|---|---|
| CVE-2026-114583 | `pkg:apk/wolfi/python-3.15@3.15.0_git20261017-r4` | `not_affected` | `vulnerable_code_not_in_execute_path` |

**Justification technique :** la faille touche `tarfile.extractall()` avec `filter="tar"`. L'API n'importe pas le module `tarfile` et n'extrait aucune archive : le code vulnérable est présent dans l'interpréteur, mais jamais appelé.

**Justification métier :** la faille n'a pas de correctif publié. Sans qualification, elle resterait une alerte permanente qu'on finirait par ignorer sans trace. La déclaration VEX documente la décision, son auteur et sa date, et Grype la lit à chaque scan via `vex-documents` dans `.grype.yaml`.

Preuve que la CVE est bien levée par le VEX, et pas seulement par `only-fixed` (scan avec `only-fixed: false`) :
```
$ grype sbom:sbom.cdx.json -o json | jq '[.ignoredMatches[] | {id: .vulnerability.id, regle: .appliedIgnoreRules}]'
[
  {
    "id": "CVE-2026-114583",
    "regle": [ { "namespace": "vex", "vex-status": "not_affected" } ]
  }
]
```

## 10. Vérification publique pour l'évaluateur

Image publiée :
```
ghcr.io/vitalikevin/tp_devsecops/api:2.0.1@sha256:abaf6c106c2ef00f7bcb8a985d8742a3eb645de73b4d570bcb8c245f000a048f
```

Signature keyless, donc pas de `cosign.pub` : la vérification se fait sur l'identité OIDC du workflow (`IDENTITY` et `ISSUER` ci-dessous).

Le job `sign` signe l'index multi-arch par son digest, puis lui attache le SBOM CycloneDX du job `sbom` en attestation. Le job `verify` refait les deux vérifications depuis ghcr.io et bloque la pipeline en cas d'échec.

Commandes (cosign 3 et jq) :
```bash
IMAGE=ghcr.io/vitalikevin/tp_devsecops/api@sha256:abaf6c106c2ef00f7bcb8a985d8742a3eb645de73b4d570bcb8c245f000a048f
IDENTITY=https://github.com/vitalikevin/tp_devsecops/.github/workflows/ci.yaml@refs/tags/v2.0.1
ISSUER=https://token.actions.githubusercontent.com

cosign verify "$IMAGE" --certificate-identity "$IDENTITY" --certificate-oidc-issuer "$ISSUER"

cosign verify-attestation "$IMAGE" --type cyclonedx \
  --certificate-identity "$IDENTITY" --certificate-oidc-issuer "$ISSUER" > /dev/null

cosign verify-attestation "$IMAGE" --type cyclonedx \
  --certificate-identity "$IDENTITY" --certificate-oidc-issuer "$ISSUER" \
  | jq -r .payload | base64 -d | jq .predicate > sbom-certifie.cdx.json
```

Résultats :
```
$ cosign verify "$IMAGE" --certificate-identity "$IDENTITY" --certificate-oidc-issuer "$ISSUER"
Verification for ghcr.io/vitalikevin/tp_devsecops/api@sha256:abaf6c106c2ef00f7bcb8a985d8742a3eb645de73b4d570bcb8c245f000a048f --
The following checks were performed on each of these signatures:
  - The cosign claims were validated
  - Existence of the claims in the transparency log was verified offline
  - The code-signing certificate was verified using trusted certificate authority certificates

$ jq -r '.bomFormat, .specVersion' sbom-certifie.cdx.json
CycloneDX
1.7
$ jq '[.components[] | select(.type != "file")] | length' sbom-certifie.cdx.json
44
```
Le SBOM extrait du registre contient les mêmes 44 composants que `sbom.cdx.json` (section 9).
