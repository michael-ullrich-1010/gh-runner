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

Das Skript ist idempotent: Bereits vorhandene Runner werden übersprungen.

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
