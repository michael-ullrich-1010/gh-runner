# gh-runner

GitHub Actions self-hosted Runner auf einem Windows-Rechner einrichten, mit **einem einzigen Browser-Login**.
Keine GitHub App, kein PAT, kein Docker.

## Einrichten (neuer Rechner)

1. PowerShell **als Administrator** öffnen.
2. Skript holen:
   ```powershell
   irm https://raw.githubusercontent.com/michael-ullrich-1010/gh-runner/main/setup-runners.ps1 -OutFile setup-runners.ps1
   ```
   (Bei privatem Repo stattdessen herunterladen bzw. klonen.)
3. Ausführen:
   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass -Force
   .\setup-runners.ps1 -Orgs <org> -Count 2 -Labels z8
   ```
4. Browser öffnet sich → bei GitHub anmelden und bestätigen.
5. Prüfen: *Org → Settings → Actions → Runners* → Runner stehen auf **Idle**.

Das Skript ist idempotent: Bereits registrierte Runner werden nicht neu angelegt, ein gestoppter
Service wird aber gestartet.

> **Deutsches Windows:** `config.cmd` trägt dort `NT-AUTORITÄT\Netzwerkdienst` als Dienstkonto ein,
> der Service startet dann nicht (Fehler 1068, *„Abhängigkeitsdienst konnte nicht gestartet werden“*).
> Das Skript setzt deshalb immer das sprachneutrale `NT AUTHORITY\NetworkService`. Von Hand:
>
> ```powershell
> Get-CimInstance Win32_Service -Filter "Name='<service>'" |
>   Invoke-CimMethod -MethodName Change -Arguments @{ StartName='NT AUTHORITY\NetworkService'; StartPassword='' }
> ```

| Parameter | Bedeutung | Default |
|---|---|---|
| `-Orgs` | Eine oder mehrere Orgs (`org-a,org-b`) | Pflicht |
| `-Count` | Runner pro Org (= parallele Jobs) | `1` |
| `-Labels` | Zusätzliche Labels | `local` |
| `-Root` | Installationsordner | `C:\runners` |

Jeder Runner erhält zusätzlich den Rechnernamen als Label.

## Im Workflow verwenden

```yaml
runs-on: [self-hosted, windows, z8]
```

## Lokal zuerst, sonst GitHub-hosted (Fallback)

GitHub kennt keinen eingebauten Fallback: Ein Job mit `runs-on: [self-hosted, …]` wartet sonst bis
zu 24 h auf einen Runner. Der wiederverwendbare Workflow
[`pick-runner.yml`](.github/workflows/pick-runner.yml) prüft deshalb vorab per API, ob ein passender
lokaler Runner **online und frei** ist, und liefert das passende `runs-on`.

Vollständiges Beispiel: [`examples/ci-with-fallback.yml`](examples/ci-with-fallback.yml)

```yaml
jobs:
  pick:
    uses: michael-ullrich-1010/gh-runner/.github/workflows/pick-runner.yml@v1
    secrets:
      RUNNER_STATUS_TOKEN: ${{ secrets.RUNNER_STATUS_TOKEN }}
  build:
    needs: pick
    runs-on: ${{ fromJSON(needs.pick.outputs.runner) }}
```

| Input | Bedeutung | Default |
|---|---|---|
| `self-hosted-labels` | JSON-Array, alle Labels müssen am Runner vorhanden sein | `["self-hosted","windows","z8"]` |
| `fallback` | GitHub-hosted Runner | `windows-latest` |
| `org` | Org, deren Runner geprüft werden | Owner des aufrufenden Repos |

**Einmalig pro Org:** Fine-grained PAT mit *Organization → Self-hosted runners: Read-only* erstellen
(Browser) und als Org-Secret hinterlegen:

```powershell
gh secret set RUNNER_STATUS_TOKEN --org <org> --visibility private
```

Der Fallback greift automatisch, wenn …
- das aufrufende Repo **öffentlich** ist (lokale Runner nie für öffentliche Repos),
- das Secret fehlt (z. B. bei PRs aus Forks) oder die API-Abfrage fehlschlägt,
- kein passender Runner online **und** frei ist.

Grenzen: Zwischen Prüfung und Jobstart kann der Runner belegt werden – dann wartet der Job. Der
Vorab-Job kostet pro Lauf einige Sekunden GitHub-hosted Minuten. Der Build muss auf beiden Runnern
laufen (Toolchain im Workflow installieren, z. B. `actions/setup-node`).

> Reusable Workflows aus einem **privaten** Repo sind nur für Repos desselben Owners nutzbar.
> Für Repos anderer Orgs muss dieses Repo **öffentlich** sein.

## Entfernen (z. B. vor dem Ausmustern des Rechners)

```powershell
.\remove-runners.ps1
```

## Voraussetzungen und Hinweise

- **Org-Owner-Rechte** in jeder angegebenen Org (Scope `admin:org`).
- Ein Runner gehört immer zu **genau einer Org** – pro Org wird eine eigene Instanz angelegt.
- Services laufen als `NETWORK SERVICE`. Toolchains (Node, Python, .NET …) selbst installieren.
- Der Runner aktualisiert sich selbst; nur ausgehendes HTTPS nötig.

## Sicherheit

- Runner **nie öffentlichen Repos** zuordnen (Fork-PRs könnten Code auf dem Rechner ausführen).
  In der Org unter *Runner groups* einschränken.
- Nichts Geheimes einchecken (`.env`, `.pem`, Tokens) – siehe `.gitignore`.
- Das Skript läuft als Administrator: `main` schützen, nur eigene Schreibrechte.
