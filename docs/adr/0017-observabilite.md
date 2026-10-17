# ADR-017 — Observabilité

- **Statut** : Acceptée (2026-09-22, validation du blueprint)

| Option                                                                                            | Avantages                                | Inconvénients                            |
| ------------------------------------------------------------------------------------------------- | ---------------------------------------- | ---------------------------------------- |
| **Sentry (erreurs/crashs/perf mobile+web+API) + OpenTelemetry → Grafana (Prometheus/Loki/Tempo)** | Standard ouvert, portable, coût maîtrisé | Deux outils à administrer                |
| Datadog / New Relic                                                                               | Tout-en-un                               | Coût élevé à l'échelle                   |
| Natif cloud (CloudWatch/Cloud Logging)                                                            | Intégré, zéro installation               | Corrélation et UX moindres, verrouillage |

**Recommandation : option 1** (versions managées au début). Détails : [12-devops-monitoring.md](../blueprint/12-devops-monitoring.md) §5.

## Mise en œuvre (constat du 2026-10-17)

- Sentry (erreurs 5xx et file des morts, données personnelles filtrées) et OpenTelemetry (exporteur OTLP, collecteur local `otel-collector`) : en place, **inactifs tant que les variables ne sont pas fournies**.
- Pas encore de Grafana/Prometheus/Loki/Tempo.
