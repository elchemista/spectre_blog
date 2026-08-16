---
title: "An Enterprise Agent Is Not a Chatbot with Production Credentials"
slug: "enterprise-agents-spectre-control-security"
lang: "en"
status: published
date: 2026-08-16
updated: 2026-08-16
category: "Software Development"
tags: ["Elixir","OTP","AI agents","Spectre","enterprise AI","security","audit","testing"]
seo_title: "Spectre for Governed Enterprise AI Agents"
seo_description: "See how Spectre 0.3.2 governs enterprise Agents with authority, Policy, recovery, Ledger, and Lab for auditing, debugging, and realistic failure tests."
cover_alt: "An operations team controls a Spectre Agent with Policies, checkpoints, Receipts, and testing tools before it acts on company systems"
---

A chatbot that gets an answer wrong creates an awkward conversation.

An Agent with production credentials that gets something wrong creates an
incident.

The enterprise problem lives in that distance. It does not begin when we add
an SSO logo to the login page, choose a larger model, or rename a demo a
"copilot." It begins when software can act on behalf of a person or a company
and we must answer questions far less glamorous than a benchmark:

- who authorized this operation?
- which version of the Agent proposed it?
- what had already been persisted before the crash?
- is repeating the operation safe?
- can we stop it, revoke it, and reconstruct what happened?

I built [Spectre 0.3.2](https://github.com/elchemista/spectre/tree/0.3.2)
starting from questions like these. Not to make the model more intelligent, but
to make delegation governable.

So when I say Spectre can be the best choice for an enterprise Agent, I do not
mean "best for every chatbot." I mean best when control, durability, recovery,
audit, and authority are system requirements, not notes added at the end of the
project.

## Enterprise begins where the demo ends

The typical Agent demo has a reassuring shape:

1. build a prompt;
2. call a model;
3. let it choose a tool;
4. execute the tool;
5. repeat until the model says it is done.

It is a great way to understand an idea. It is also an incomplete description
of a real operational system.

That loop does not say who owns state when two requests arrive concurrently.
It does not say whether an Action approved yesterday remains authorized after
a revocation. It does not distinguish provisional stream text from a canonical
Result. It does not know whether an external provider issued a refund before
the connection dropped. It does not explain what happens when the process
restarts with a different Definition.

Many frameworks are excellent at reducing the time needed to reach the first
tool call. That is a legitimate goal. The problem is that several abstractions
leave outside their model the questions a company meets after the first
success: ownership, fencing, revocation, ambiguous persistence, idempotency,
privacy, auditing, and failure testing.

Spectre starts there.

## A real case: the Agent handling a dispute

Imagine an Account Operations Agent used by a SaaS company.

A customer opens a dispute through the portal. Later they reply on WhatsApp,
then an operator continues the case in an internal console. The Agent must see
one enterprise Subject, not three disconnected conversations. It must collect
account events, analyze the history, propose a resolution, and, when
authorized, issue a refund or temporarily suspend a service.

Research may take minutes. A Vigil can check whether the payment has been
reconciled. A Work can continue after the Turn that started it has ended.
Meanwhile, an operator can correct the objective, pause the work, or revoke the
Agent's authority.

Now the interesting case arrives: the payment provider accepts the refund, but
the process dies before receiving confirmation. On restart we have two
unpleasant options.

If we retry blindly, we may refund twice. If we do nothing, we may leave the
customer without a refund. The correct answer is not "ask the model what it
thinks." The correct answer is to preserve the ambiguous outcome, reconcile it
using external evidence, and prevent a new Runner from acting with stale
authority.

This is not an exotic case. It is the kind of problem that appears as soon as
an Agent stops writing text and begins touching the world.

## The point is not the loop, it is who owns it

Spectre separates concepts that look identical in a demo:

| Concept | Responsibility |
| --- | --- |
| Definition | The immutable shape of the Agent, including available Flows, Policies, Skills, and Actions |
| Instance | The sole local owner of the AgentRef and Subject pair |
| Turn | One conversational decision with one outcome |
| Run | The governed continuation of work, with generations and fencing |
| Invocation | An identified nondeterministic call, including inference |
| Policy | The deterministic machine deciding when new authority is required |
| Effect | The approved operation that the host system can execute separately |
| Receipt | Evidence bound to a boundary and canonical state, not a magical exactly-once promise |

This separation changes how we reason about the system.

The model can propose. A Policy can request approval. The Instance can commit
canonical state. The host application can check RBAC, credentials, and
transactions before executing the Effect. None of these steps needs to hide in
a sentence inside the system prompt.

## The Agent exists as verifiable code

The minimal shape of our Account Operations Agent could look like this:

~~~elixir
defmodule MyApp.AccountOpsActions do
  def issue_refund(args, ctx) do
    idempotency_key = Keyword.fetch!(ctx.opts, :idempotency_key)

    MyApp.Billing.issue_refund(
      ctx.assigns.case_id,
      args,
      idempotency_key: idempotency_key
    )
  end
end

defmodule MyApp.AccountOpsAgent do
  use Spectre.Agent,
    id: :account_operations,
    prompt_root: "priv/agents/account_operations/prompts"

  model(MyApp.LLM)
  router(via: [:regex, :embedding, :classifier])

  actions MyApp.AccountOpsActions do
    protect(:issue_refund, with: :refund_confirmation)
  end

  before_action(:issue_refund,
    run: {MyApp.AccountOpsGuards, :refund_authorized}
  )

  policy :refund_confirmation do
    request(:confirm_refund)
    accept(:refund_approved, regex: ~r/^approve refund$/i)
    reject(:refund_rejected, regex: ~r/^(reject|cancel) refund$/i)
    otherwise(ask: :confirm_refund_retry)
    attempts(3, then: :cancel_pending)
  end

  interrupt :STOP, regex: ~r/^(stop|cancel)$/i do
    run(:cancel_current)
  end

  flow :account_operations do
    on :INVESTIGATE,
      regex: ~r/\b(investigate|analyze)\b/i do
      reason(:investigate_case, temperature: 0.1)
    end

    on :PROPOSE_RESOLUTION,
      regex: ~r/\b(propose|resolve)\b/i do
      act(:propose_resolution, temperature: 0.1)
    end

    on :ISSUE_REFUND,
      regex: ~r/^issue refund$/i do
      action(:issue_refund, args: %{source: "operator"})
    end
  end
end
~~~

Here `reason/2` permits analysis without Action planning. `act/2` allows the
mounted planner to choose only from a closed Action catalog. The deterministic
route uses `action/2` to stage a known operation. In every case, `protect/2`
prevents the refund from becoming executable before the Policy.

Approval still does not execute the refund. It produces an approved and
persisted Effect. The callback receives an idempotency key, but
`MyApp.Billing` must enforce it at its own durable boundary. The guard also
reads current authorization from the enterprise system immediately before
execution.

This distinction is essential: a valid argument schema is not authorization,
and a convincing model response is not an RBAC role.

## Authority has a version and can be revoked

In Spectre, an active Definition belongs to a generation. Runs are fenced to
the identity, Definition, and authority that produced them. A temporary Runner
does not become a second owner of state. If a newer control arrives, late
events from the previous generation are rejected through fencing.

This closes a class of bugs that often appears only under load:

- an old task finishes after the operator changes the objective;
- a retry delivers the same result twice;
- a provider responds after cancellation;
- a restarted Worker attempts to write over newer state;
- an Action remains technically available after authority has been revoked.

The BEAM is especially well suited to this model. Supervised processes,
mailboxes, isolation, and restarts are excellent tools, but they do not define
application truth on their own. Spectre adds canonical ownership, generations,
commits, and recovery protocols above those primitives.

OTP helps you restart a process. Spectre must also decide whether that process
may still speak for the Agent.

## Spectre Ledger: debugging starts with evidence

[Spectre Ledger 0.1.0](https://github.com/elchemista/spectre_ledger)
implements two public boundaries already present in Core:
`Spectre.Instance.CheckpointStore` and `Spectre.Receipt.Sink`.

It does not replace the Instance, add a second scheduler, or try to record
every internal runtime movement. It stores, as append-only evidence, the
checkpoints Spectre actually persists and the Boundary Receipts Spectre emits
at nondeterministic or authority boundaries.

The dependencies have their own versions. Ledger `0.1.0` and Lab `0.1.0` are
not "older" copies of Spectre: those numbers describe separate packages, and
the current releases explicitly target Core `0.3.2`.

~~~elixir
defp deps do
  [
    {:spectre, "~> 0.3.2"},
    {:spectre_ledger,
     github: "elchemista/spectre_ledger",
     branch: "main"},
    {:spectre_lab,
     github: "elchemista/spectre_lab",
     branch: "main",
     only: [:dev, :test]}
  ]
end
~~~

In production, Ledger uses an Ecto Repo owned and supervised by the
application. It does not take control of the database or hide topology from
the operations team.

~~~console
mix spectre_ledger.gen.migration
mix ecto.migrate
mix spectre_ledger.doctor --backend postgres --repo MyApp.Repo --strict
~~~

~~~elixir
ledger_opts = [
  backend: :postgres,
  repo: MyApp.Repo,
  namespace: "account-operations"
]

checkpoint_store = Spectre.Ledger.checkpoint_store(ledger_opts)
receipt_sink = Spectre.Ledger.receipt_sink(ledger_opts)

subject = Spectre.Subject.new({:support_case, "CASE-4821"})

{:ok, instance} =
  Spectre.summon(
    agent: MyApp.AccountOpsAgent,
    subject: subject,
    checkpoint_store: checkpoint_store,
    receipt_mode: :required,
    receipt_sink: receipt_sink
  )
~~~

With `receipt_mode: :required`, Spectre stages the payload, commits the
canonical outbox, crosses the checkpoint durability barrier, and performs an
idempotent append before completing the boundary. With `:observational`, a
sink problem does not block the Run.

This choice is explicit because the two modes answer different needs.
Telemetry for a suggestion may be observational. Evidence that a protected
Effect crossed a boundary may be required.

For an operational investigation, we can read and verify the chain:

~~~elixir
{:ok, envelopes} = Spectre.Ledger.receipts(instance_ref, ledger_opts)
{:ok, report} = Spectre.Ledger.verify_receipts(instance_ref, ledger_opts)
{:ok, entries} = Spectre.Ledger.receipt_entries(instance_ref, ledger_opts)
~~~

The report preserves the difference between physical append order and
canonical revision. It does not reorder history to make it look cleaner.

That is useful enterprise debugging: not "show me everything the process
thought," but "verify which evidence is bound to which state and boundary."

## Spectre Lab: reproduce conditions, not replay myths

[Spectre Lab 0.1.0](https://github.com/elchemista/spectre_lab) takes that
evidence into an offline environment and adds isolated testing tools. It can
load a verified checkpoint Bundle, compare two playbacks by identity, verify a
detached Receipt chain, and drive the real streaming runtime with deterministic
fixtures.

For example, it can test inference without opening a network connection:

~~~elixir
script =
  Spectre.Lab.Inference.StreamScript.text!(
    "Refund requires manual approval.",
    chunk_size: 4
  )

{:ok, stream} =
  Spectre.stream(instance, "Analyze case CASE-4821",
    model: MyApp.TestModel,
    plan_actions?: false,
    stream_adapter: Spectre.Lab.Inference.StreamAdapter,
    stream_adapter_opts: [script: script, observer: self()]
  )

events = Enum.to_list(stream)
~~~

This is deterministic fixture delivery through the real runtime. It is not
deterministic reproduction of an earlier model call. The difference may look
like cautious terminology, but it is exactly the kind of precision that
prevents a false guarantee in tests.

Lab can also inject the failure we actually care about, not just a generic
`{:error, :boom}`:

~~~elixir
{:ok, controller} =
  Spectre.Lab.Fault.Controller.start_link(
    script: %{
      compare_and_swap: [
        {:commit_then_return,
         {:error, {:ambiguous, :lost_ack}}}
      ]
    }
  )

faulty_store =
  {Spectre.Lab.Fault.CheckpointStore,
   controller: controller,
   delegate: checkpoint_store}
~~~

`commit_then_return` means the delegate committed the write, but the caller
receives an ambiguous outcome, just as when an acknowledgement is lost. A test
can therefore exercise the production recovery and reconciliation path, not a
special Lab shortcut.

The same mechanism exists for `ReceiptSink`, including append and payload
staging. `Spectre.Lab.TestCase` also supplies a test-owned sandbox and a closed
`IOFuse`. The fuse blocks only I/O explicitly routed through it, so Lab does
not pretend to be a universal operating system sandbox.

That honesty about boundaries is a security feature, not a limitation to hide.

## What Spectre solves that often sits outside the framework

Let us return to our Account Operations Agent.

| Operational problem | Spectre boundary |
| --- | --- |
| Web, WhatsApp, and the console open three sessions for the same customer | Subject and Instance define one canonical owner |
| Two concurrent requests update the same Agent | The Instance sequences state and the Checkpoint Store uses CAS |
| An old result arrives after stop or update | Generations, Runs, and epochs apply fencing |
| The model proposes a refund with invalid arguments | A closed catalog and bounded JSON Schema are validated during planning and execution |
| An operator must approve a sensitive Action | Policy is deterministic and approval is a separate commit from execution |
| The process dies after a possible write | The outcome remains ambiguous until evidence permits reconciliation |
| The team must know what crossed a boundary | Receipts bind evidence, Definition, and canonical roots |
| Recovery, backpressure, and provider failures need testing | Lab uses virtual streaming and fault injection at public interfaces |
| Work lasts longer than the message that started it | Works and Vigils share the governed operational runtime |

These are not dashboard accessories. They are system properties.

## Security also means declaring where Spectre ends

Spectre is a runtime boundary, not a complete enterprise authorization system.
Its [security model](https://github.com/elchemista/spectre/blob/0.3.2/SECURITY.md)
says so clearly.

The host application must still:

- authenticate users and operators;
- authorize the real resource and tenant;
- protect and rotate credentials;
- enforce RBAC and database policies;
- make Effects idempotent at the external boundary;
- encrypt checkpoints and Receipts where required;
- define retention, backups, and network isolation;
- run risky code inside an appropriate sandbox.

Spectre does not promise immunity to prompt injection. It marks dynamic
content as data in `Prompt.Plan`, constrains what a planner may select,
validates arguments, and keeps authority outside generated text. Those are
structural defenses, but they do not turn hostile input into trusted input.

Ledger is equally precise about its boundary: content addressing proves
integrity, not confidentiality or authorization. An untrusted external Bundle
must be verified on an isolated, restricted node because Foundation decoding
may load BEAM modules already present, including modules with `@on_load`.

An enterprise platform is not credible because it says "secure." It is
credible when the boundary, owner, and evidence can be identified.

## Ledger and Lab are not a time machine

It is equally important to say what these tools do not promise.

Ledger records the checkpoints Core chooses to persist. Spectre may coalesce
writes, so a Bundle does not necessarily contain every internal revision. Lab
plays back those verified checkpoints, not the whole causal execution. Neither
repeats a model call or an external Effect as if the world were deterministic.

Receipts do not make a remote provider exactly once. An idempotency key does
not make an API idempotent if that API ignores it. An ambiguous outcome does
not become a failure merely because a retry would be convenient.

These sentences may look less attractive on a landing page. In production,
they are far more useful than an impossible guarantee.

## When Spectre really is the best choice

Spectre is a strong candidate when a company:

- uses Elixir and wants Agents with native BEAM semantics;
- needs durable Agents that outlive a single HTTP request;
- has sensitive Actions requiring verifiable Policies and approvals;
- must handle concurrency, cancellation, revocation, and restart without ghost state;
- wants observable nondeterministic boundaries with verifiable evidence;
- must test ambiguous faults, streaming, and recovery before production;
- prefers explicit contracts over critical behavior hidden in prompts.

If the requirement is a promotional chatbot built over a weekend, Spectre may
be more structure than necessary. If the team does not use the BEAM and only
wants to try a tool loop, shorter paths exist.

But when an Agent must work for hours, survive crashes, share a Subject across
channels, cross enterprise boundaries, and explain what it did, structure is
not bureaucracy. It is the product.

## Built with real cases in mind

Spectre did not begin with the idea that a sufficiently long prompt could
describe a distributed system.

It began with the Agent that really sends a message. The one that can delete an
account or restart a service. The research Work that continues after the HTTP
response. The Vigil that wakes tomorrow. The operator who changes the
objective while a provider is still generating. The checkpoint that may have
been written before the acknowledgement disappeared. The rejected Policy. The
updated Definition while Runs from the previous version still exist.

That is why responsibilities remain separate across the ecosystem. Core
governs. Ledger retains durable evidence. Lab verifies playback and failures.
Other packages can add perception, memory, planning, channels, or missions
without becoming a second owning runtime.

I do not want the Agent to look autonomous during the demo. I want it to remain
controllable after the demo ends and real work begins.

## The real enterprise feature is the ability to say no

An enterprise Agent is not a model with more permissions. It is a system able
to say:

"This operation is outside your current authority."

"This approval has expired."

"The write may have happened, so I will not repeat it blindly."

"This text is provisional, the Result is not canonical yet."

"This evidence is intact, but your role may not read its data."

That is less magical than an infinite loop with access to everything. It is
also much closer to something a company can responsibly put into production.

Spectre does not make the model more intelligent. It makes delegation
governable.
