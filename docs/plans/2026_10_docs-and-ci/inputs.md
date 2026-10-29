# Inputs

The user's framing for this work, captured **verbatim**. Do not paraphrase, summarize, or "clean up" — interpretation belongs in `10_target_shape.md`, and we need the unfiltered source to check that interpretation later.

## Source

### The grading rubric (`docs/LB3_Projektarbeit_WIR.md`), the two criteria this plan targets, quoted verbatim

> | 1 | Systemdokumentation & Architekturüberblick | 5 Pkt | Keine Dokumentation vorhanden. | Textlastige Beschreibung, rudimentäres Diagramm. Systemarchitektur nur durch Code-Inspektion verständlich. | Präziser One-Pager mit Diagramm; Service-Grenzen, Protokolle und Verantwortlichkeiten sind klar erkennbar. | Umfassende Visualisierung inkl. synchroner/asynchroner Datenflüsse, Fehlerbehandlung und Deployment-Topologie. |
> | 8 | Autonomie, Repo-Struktur & Deployment | 5 Pkt | System kann nicht gerstartet werden. | Vermischte Repositories; gemeinsame Domain-Bibliotheken; komplexes manuelles Starten nötig. | Repo Trennung eingehalten; strikte Trennung; Gesamtsystem mit einem Befehl startbar. | Isolierte CI-Pipelines (Linter/Tests). Services sind Containerisiert. |

### The user's instruction to act on the audit

> Yes please, turn these into plans to be tackled.

(Said in response to being shown a full audit of the project against all 9 rubric criteria. The user confirmed: 3 themed plans — this one covering criteria 1/8 together, both "project hygiene" fixes — skipping straight to an implementation doc rather than the full staged process, since neither has a real design decision to weigh.)

## Notes

This plan's starting point is a live-codebase audit performed earlier in this session. Findings `40_implementation.md` should verify fresh, not take on faith:

- **Documentation (criterion 1):** the root `README.md` is a flat bullet list (service names + infra tool names), no diagram. Each of the 5 service repos' `README.md` is a single sentence (e.g. `M321_TBZ_Phaseolus_Order/README.md`: "Service handling ordering food."). `docs/plans/2026_09_phaseolus-architecture/` (8 files) contains zero diagram syntax anywhere (no mermaid, no ASCII art, no images) despite thoroughly documenting the architecture in prose.
- **CI/Deployment (criterion 8):** each service lives in its own repo with its own `.csproj` and no shared library/`ProjectReference` between them — repo isolation is already clean. `setup.sh` is a genuine single-command full-system bring-up (minikube → infra Helm → clone+build all 5 services → Argo CD bootstrap → port-forwards). Each service has its own `Dockerfile`. The one gap: **zero `.github/workflows` (or any CI config) exist in any of the 6 repos** — no linting, no automated tests run anywhere.
