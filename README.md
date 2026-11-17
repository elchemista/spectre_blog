# Spectre articles

Articles live under `content/<language>/` and follow ExBlog's Markdown/frontmatter contract. English and Italian translations are stored separately.

## Current Spectre 0.4 guidance

The current application architecture is **Stack → Agent → Server**, with GAM (Governed Act Model) mediating the application's declared consequences. Read the [English documentation](https://spectre.guide/en/docs/overview) or [documentazione italiana](https://spectre.guide/it/docs/overview), then the [0.3 → 0.4 migration guide](https://spectre.guide/en/docs/migration) before upgrading an older application.

## Spectre 0.4 published series

The release overview and three companion deep dives are published in English and Italian (`status: published`).

| Topic | English | Italiano |
| --- | --- | --- |
| Release overview: agents, authority and control | [Read article](content/en/2026-11-17-spectre-0-4-agents-authority-and-human-control.md) | [Leggi articolo](content/it/2026-11-17-spectre-0-4-agenti-autorita-e-controllo-umano.md) |
| New ergonomics: Stack, Agent routes, Server, RAM and storage | [Read article](content/en/2026-11-17-spectre-0-4-stack-agent-routes-server-architecture.md) | [Leggi articolo](content/it/2026-11-17-spectre-0-4-stack-agent-route-server-architettura.md) |
| Why GAM exists: Mandate, Evidence, Act, Duty | [Read article](content/en/2026-11-17-why-i-created-gam-governed-act-model.md) | [Leggi articolo](content/it/2026-11-17-perche-ho-creato-gam-governed-act-model.md) |
| External approval: invoice request between two agents | [Read article](content/en/2026-11-17-spectre-external-gam-invoice-approval-between-agents.md) | [Leggi articolo](content/it/2026-11-17-spectre-0-4-approvazione-fattura-tra-agenti.md) |

A [companion Elixir invoice approval fixture](examples/spectre_0_4_external_invoice_approval.exs) adapts the core external-approval test to a *simulated* invoice operation. Run it from a Spectre 0.4 checkout with `mix run /path/to/spectre_blog/examples/spectre_0_4_external_invoice_approval.exs`. It does not send a real invoice.

## Historical articles

The August 2026 articles describe the releases and APIs available when written, including the retained Instance/Run runtime. Their publication dates and version-specific claims are preserved. A dated notice links to current 0.4 guidance; examples from that archive should not be copied as current AgentServer APIs without following the migration guide.

Publishing an article is an explicit editorial action: new Markdown with `status: draft` is not part of the public article list.
