---
title: "In Europe an Agent Must Do More Than Work: Spectre 0.3.3, GDPR, the AI Act, and ISO"
slug: "spectre-0-3-3-gdpr-ai-act-iso-europe"
lang: "en"
status: published
date: 2026-08-23
updated: 2026-08-23
category: "AI Governance"
tags: ["Spectre","GDPR","AI Act","ISO 42001","ISO 27701","AI governance","privacy","EU market"]
seo_title: "Spectre 0.3.3 for GDPR, the AI Act, and ISO"
seo_description: "Spectre 0.3.3 brings governed erasure, evidence, policy, and observability to a runtime designed for GDPR, the AI Act, and ISO work."
cover_alt: "A Spectre Agent controlled through policy, verifiable evidence, and governed erasure for the European market"
---

Imagine that you are a European agency presenting a new Agent to a client.

The demo works well. The client writes a request, the Agent checks a set of
documents, calls an external service, and prepares an answer. Everything feels
fast, intelligent, and ready for production.

Then the security lead or the DPO joins the meeting, and the questions that
were absent from the demo begin.

Where does the conversation data remain? Which model received it? How can we
truly erase the state of one customer? What happens if an old backup brings it
back? Can we prove which version of the Agent made a decision? Can a person
stop an action before it reaches the outside world? If we change providers, do
we also lose our ability to explain the system?

At that moment, the quality of the model answer is no longer the only thing
that matters. What matters is whether the architecture has credible answers.

This is where many European AI projects slow down. The model is not the
problem. The problem is that the system around it began as a demo and must now
be transformed into something a company can govern.

With [Spectre 0.3.3](https://github.com/elchemista/spectre/tree/0.3.3), I tried
to move that moment much closer to the beginning. Spectre does not claim that
installing a library makes a company automatically compliant with GDPR or the
AI Act. No runtime can determine the lawful basis for processing, sign a
supplier agreement, or obtain an ISO certification on behalf of an
organisation.

It can change the point from which the organisation starts. Instead of adding
control, erasure, and evidence after the Agent has already grown, the team can
build the Agent on boundaries that exist from the first day.

## GDPR enters the runtime before an erasure request

When GDPR appears in an AI project, the conversation often ends with a privacy
notice and a checkbox. The regulation asks for much more.

Its [principles for processing personal data](https://data.europa.eu/eli/reg/2016/679/oj)
include defined purposes, data minimisation, limited storage, integrity, and
confidentiality. Data protection by design asks organisations to place those
principles inside technical and organisational measures, not to remember them
only when the project is almost finished.

For an Agent, this creates an important choice: observe the system without
copying the entire conversation everywhere.

The Spectre Journal was designed around this separation. It is not chat
history and it is not a generic log container. It records structured runtime
decisions concerning routing, policy, lifecycle, execution, and persistence,
while excluding conversation text, Effect arguments, Action results, and raw
provider errors by default. If an application chooses to include content, it
must do so explicitly and can apply redaction and retention inside its own
Store.

That difference feels small until someone has to explain why a sentence written
by a customer was copied into five observability systems. Spectre starts from
the opposite idea. To understand a decision, it first tries to preserve the
shape of the decision rather than all the private content that surrounded it.

Boundary receipts follow the same principle. They can connect a nondeterministic
boundary or an authority decision to canonical state and the active Definition
without turning every private detail into a public log. The sink remains the
responsibility of the host, which must apply encryption, customer isolation,
access control, and retention. Spectre does not pretend that the place where
evidence is stored is automatically safe. It makes the contract of that place
explicit.

## Erasing an Agent without allowing it to return

The most concrete addition in version 0.3.3 is
[governed Instance erasure](https://github.com/elchemista/spectre/blob/0.3.3/docs/ERASURE.md).

Suppose a customer asks for their data to be erased and the organisation has
determined that the request falls within the
[right to erasure](https://data.europa.eu/eli/reg/2016/679/oj). Deleting one
database row is not enough when the Agent is still alive in memory, a worker
can write another checkpoint, or an old backup can restore the state that was
just removed.

Spectre treats this operation as maintenance rather than as a normal Agent
action. It first lets the operator build a plan that does not touch data and
checks whether the configured adapters expose the necessary capabilities.
During execution, it requires the exact stable key as confirmation, refuses a
locally active Instance, and acquires maintenance ownership that cannot replace
a live owner.

Only then does Spectre coordinate the data visible to the core. It removes
Journal records bound to that exact Instance, deletes payloads still pending in
receipts, and erases the canonical checkpoint. The Checkpoint Store must then
install a durable marker and read it back. That marker prevents a late writer
from recreating the same identity after erasure.

The result is not merely a message saying that the operation completed.
Spectre returns proof limited to the components it actually coordinated. Its
conformance tests also verify that erasure can be repeated safely, that it does
not touch a neighbouring Instance, and that a race between erasure and a write
produces one authoritative result.

The most serious part of this design is what Spectre does not claim to have
erased.

Application state may live in another database. Memory may be managed through
an external adapter. A provider may retain requests according to the contract
chosen by the organisation. Telemetry, exports, replicas, and backups all have
their own lifecycle. The
[Spectre data map](https://github.com/elchemista/spectre/blob/0.3.3/docs/DATA_LIFECYCLE.md)
shows these boundaries instead of hiding them behind an optimistic answer.

That honesty is itself a compliance feature. A DPO does not need a library that
claims to have erased everything. A DPO needs to know exactly what was erased,
what remains, and who is responsible for it.

## The AI Act looks at the system around the model

The same reasoning applies to the AI Act.

When we read the
[European regulation on artificial intelligence](https://data.europa.eu/eli/reg/2024/1689/oj),
the demanding requirements for systems that fall into high risk cases are not
limited to model accuracy. They concern continuous risk management,
documentation, event recording, human oversight, robustness, security, and
monitoring over time.

This is a system problem.

In Spectre, the model may classify a request or propose an action, but it does
not own final authority. An Effect describes something that may happen. Policy
and deterministic lifecycle rules decide which gates are necessary, while the
host keeps credentials and execution power.

Version 0.3.3 makes human oversight even clearer through policies resolved by
an external source. A protected request can remain pending while the normal
conversation continues. Approval must arrive from the declared host source and
cannot be invented by the model inside an answer.

That difference matters for an agency building, for example, an Agent that can
prepare a refund, change a contract, or send an official communication. The
person is not added as a sentence in the prompt. Human approval becomes a
runtime gate that the model cannot skip.

The Journal helps explain which route and policy were applied. Receipts connect
external boundaries to state digests and the active Definition. Definitions
and Manifests are immutable and identifiable, so a decision can be traced to
the configuration that existed at that moment rather than the configuration
found in the repository today.

When behaviour changes, Spectre governance separates proposal, evaluation,
approval, and activation. A change proposed by a model remains inert.
Protected tests cannot be replaced by easier examples created by the candidate
itself. If the new version performs worse, the previous Definition remains
available for rollback.

This does not complete the risk management system required by the AI Act. It
provides technical facts that such a system can use. Without identifiable
versions, decision evidence, and repeatable tests, even the best company
procedure is forced to trust a story written after the incident.

## When a control becomes evidence

For an enterprise client, it is not enough that an adapter appears correct.

An agency can replace the Checkpoint Store, the Journal, the receipt sink, or
the system that assigns distributed ownership. Once that happens, the
guarantees of the core also depend on code written outside the core.

Spectre 0.3.3 makes this frontier verifiable through
[executable conformance contracts](https://github.com/elchemista/spectre/blob/0.3.3/docs/FOUNDATION_CONFORMANCE.md).
An erasure adapter is not considered valid merely because it exports a
function with the correct name. It must demonstrate exact erasure, isolation
of neighbouring identities, repeatability, and rejection of stale writes. The
distributed owner profile verifies concurrent races, authority transfer, and
fencing.

Spectre again avoids an impossible promise. These tests do not certify database
replication, backup policy, or deployment topology. They prove only the
semantics they can observe. But they turn an important part of integration from
informal trust into an executable contract.

That distinction matters during an audit. Saying that a component should
behave in a certain way is documentation. Showing a report produced by the same
public contract used during development is evidence.

## A bridge toward ISO, not an automatic certification

The ISO standards relevant to AI do not certify an isolated library. They look
at how an organisation assigns responsibility, manages risk, maintains
processes, verifies results, and improves over time.

[ISO/IEC 42001](https://www.iso.org/standard/42001) defines an artificial
intelligence management system. Spectre does not create that system for the
organisation, but it can feed it with identifiable Definitions, policies,
evaluations, receipts, Journal records, and activation evidence. These
artifacts help connect what the organisation declares to what the runtime
actually did.

[ISO/IEC 42005](https://www.iso.org/standard/42005) focuses on impact
assessment throughout the lifecycle. The separation between declared and
observed behaviour, evaluation reports, and the history of approved changes
becomes useful here. [ISO/IEC 23894](https://www.iso.org/standard/77304.html)
addresses AI risk management, a process that can use the same tests and
evidence to verify whether a technical measure continues to work.

For security, [ISO/IEC 27001](https://www.iso.org/standard/27001) requires a
management system involving people, processes, and technology. For privacy,
[ISO/IEC 27701](https://www.iso.org/standard/27701) provides a system for
managing personal information and demonstrating accountability.

Spectre delivers none of these certificates. It makes it easier to reuse the
same technical structure when an organisation maps its controls to different
standards. Governed erasure can support a privacy control. The Journal can
support traceability and investigation. External policies can support human
oversight. Evaluations and immutable Definitions can support change management
and AI risk work.

The important word is support. An auditor must still examine context,
processes, and evidence. Spectre brings that evidence closer to the actual
behaviour of the system.

## Why this matters for European agencies

An agency does not sell code alone. It sells the ability of a client to trust
that code after the original team has finished the project.

With a framework centred mainly on the loop between prompt, model, and tool,
every enterprise requirement tends to become a separate integration. Logging
is added in one place, approval in another, erasure in an administrative
script, and behaviour versioning in a table created later. The system may work,
but no component owns the complete story.

Spectre is better suited to this side of the market because it starts with a
different question. It does not ask only how a model can run a tool. It asks
who owns state, which Definition is active, who may cross a boundary, which
evidence remains, and how an identity is erased without returning.

For a European agency, that means arriving at the client with something more
serious than a demo. The agency can show a data plan, an approval policy, an
evaluation report, a conformance report for its storage adapter, and an
erasure procedure. It
can change provider or infrastructure without moving Agent authority into the
model. It can adapt deployment to the needs of each client while preserving
the same control architecture.

This does not make Spectre better for every possible AI project. If the task is
a script that summarises ten files and then disappears, a governed runtime may
be more than necessary. But when an Agent enters company processes, touches
personal data, remains active over time, and can produce effects, the problems
Spectre treats as fundamental become exactly the problems the client will
begin to ask about.

## Responsibility remains human

There is still a boundary I do not want to hide.

Spectre does not determine whether processing has a lawful basis. It does not
write the privacy notice, classify AI Act risk by itself, complete an impact
assessment, or decide whether a transfer outside Europe is lawful. It does not
configure provider retention, encrypt the host database, or train the people
responsible for oversight.

The obligation to tell a user that they are interacting with an AI system must
also be implemented in the product experience. The runtime can preserve the
technical truth of behaviour, but the organisation must turn that truth into
transparency people can understand.

This is not a weakness. It is the correct separation of responsibility.

Compliance does not come from adding one dependency to a project. It comes
from the meeting of legal choices, organisational processes, and technical
controls. Spectre 0.3.3 works on the third part and tries to make it explicit
enough to support the other two.

For a long time, the AI market rewarded the team with the most surprising
demo. In Europe, it is becoming just as important to show that the same demo
can be limited, observed, tested, stopped, and truly erased when necessary.

This is where Spectre can become an especially strong choice for European
agencies and companies. It does not promise a shortcut to compliance. It
avoids building the Agent in a form that makes compliance almost impossible to
demonstrate later.
