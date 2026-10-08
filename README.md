# Rapport technique — API Flask / PostgreSQL

## 1. Packages GHCR

> À compléter après la première release.

```bash
docker pull ghcr.io/vitalikevin/tp_devsecops/<nom>:<x.y.z>
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

> À compléter (docker-compose).

## 5. Remédiations

**Flake8 :** 0 violation avec le `.flake8` fourni.

**Dépendances :**

| Paquet | Avant | Après | Raison |
|---|---|---|---|
| Flask | 2.3.2 | 3.1.3 | CVE-2026-27205 ; compatibilité avec Python 3.14 |
| Werkzeug | 2.3.3 | 3.1.9 | CVE-2024-34069 (HIGH) et 7 MEDIUM |
| pytest | 7.4.0 | 9.1.1 | CVE-2025-71176 |
| psycopg2-binary | non épinglé | 2.9.13 | reproductibilité |

Le venv est créé sans pip (`--without-pip`). Sinon, pip serait copié dans l'image finale, avec ses propres CVE HIGH.

## 6. Sécurisation CI/CD

> À compléter (workflow).

## 7. Preuves d'exécution

> À compléter avec les sorties de la CI.
