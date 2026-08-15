---
title: "Humans Should Govern the Loop, Not Run It"
slug: "humans-govern-loop-spectre-streaming-0-3-2"
lang: "en"
status: published
date: 2026-08-15
updated: 2026-08-15
category: "Software Development"
tags: ["Elixir","OTP","AI agents","Spectre","AI streaming","human in the loop","governance","distributed systems"]
seo_title: "Govern AI Agents with Spectre 0.3.2"
seo_description: "Learn how Spectre 0.3.2 governs inference and streaming through Instances, steering, budgets, recovery, Receipts, and explicit human boundaries in Elixir."
cover_alt: "An operator governs a Spectre Agent during incident analysis while observing provisional streaming, budgets, steering, and the canonical Result"
---

We built Agents capable of working for hours.

Then we hired a human to press "Continue" every thirty seconds.

Congratulations. We automated the work by creating a new job.

A [daily.dev collection about AI engineering in
2026](https://daily.dev/posts/ai-engineering-in-2026-agents-are-everywhere-but-humans-still-run-the-loops-t8knr6vxz)
captures the paradox well: Agents are everywhere, but humans still run the
loops. They inspect every step, copy results between systems, restart stuck
processes, watch costs, and decide whether an incomplete answer is already
trustworthy enough to use.

The problem is not that a human is present. The problem is the role we gave
them.

A human should define intent, authority, and limits. A human should intervene
when the required judgment changes. A human should not become the scheduler,
retry manager, and transactional database for a probabilistic model.

The [Spectre `0.3.2`](https://github.com/elchemista/spectre/blob/0.3.2/CHANGELOG.md)
release makes that distinction concrete. Inference becomes a
`Spectre.Invocation` owned by the Instance. Streaming is no longer just text
forwarded from a provider to a UI. It has identity, budgets, fencing,
cancellation, steering, recovery, and a precise point where a provisional
result becomes canonical.

This is not a story about making words appear on screen a little sooner. It is
a story about who owns the loop.

## The real case: an Incident Analyst that can be corrected while running

Let us build an Agent that helps during a production incident.

It receives a timeline, metrics, and notes already collected by the
application. It analyzes the evidence, proposes a hypothesis, and prepares a
readable explanation. While it is working, the operator may realize that the
first direction is too broad and write:

> Focus only on payment service timeouts after deploy `checkout-1842`.

A naive implementation appends this sentence to the prompt while the provider
is still generating. Half the answer now belongs to the old intent and half to
the new one. The UI presents both as one coherent thought. The system can no
longer say which instruction produced which text.

Spectre chooses stricter semantics: steering replaces the attempt. The old
stream terminates as `:superseded`. The new attempt receives a new Invocation
and a new epoch. The application must consume the replacement explicitly.

It is not spectacular. It is better: it is falsifiable.

## Prepare the Agent without hiding behavior in the prompt

Start with the published dependency:

~~~elixir
defp deps do
  [
    {:spectre, "~> 0.3.2"}
  ]
end
~~~

Before starting the service, we can inspect the installed contract and the
Agent Definition:

~~~console
mix spectre.doctor --agent MyApp.IncidentAnalyst --strict
~~~

[`Doctor`](https://github.com/elchemista/spectre/blob/0.3.2/docs/INSTALLATION.md)
is read-only. It checks versions, the Foundation matrix, and the
public shape of the Agent without starting package resources or calling
external adapters. It does not prove that our deployment is safe, but it finds
a much less romantic class of problems: incompatible configuration and
incomplete contracts.

The Agent Definition remains ordinary Elixir code:

~~~elixir
defmodule MyApp.IncidentActions do
  def restart_checkout(args, ctx) do
    key = Keyword.fetch!(ctx.opts, :idempotency_key)
    MyApp.Deployments.restart_checkout(args, idempotency_key: key)
  end
end

defmodule MyApp.IncidentAnalyst do
  use Spectre.Agent,
    id: :incident_analyst,
    prompt_root: "priv/agents/incident_analyst/prompts"

  model(MyApp.LLM)
  router(via: [:regex])

  actions MyApp.IncidentActions do
    protect(:restart_checkout, with: :restart_confirmation)
  end

  policy :restart_confirmation do
    request(:confirm_restart)
    accept(:confirmed_restart, regex: ~r/^confirm restart$/i)
    reject(:cancel_restart, regex: ~r/^(cancel|do not restart)$/i)
    attempts(2, then: :cancel_pending)
  end

  flow :incident_response do
    on :ANALYZE_INCIDENT,
      regex: ~r/\b(analyze|investigate|incident)\b/i,
      via: [:regex] do
      reason(:incident_analysis, temperature: 0.1)
    end

    on :RESTART_CHECKOUT,
      regex: ~r/^restart checkout$/i,
      via: [:regex] do
      action(:restart_checkout)
    end
  end
end
~~~

There are already two different boundaries here.

`reason/2` lets the model analyze and reply, but disables Action planning.
`action/1` selects a known operation protected by a deterministic Policy. The
prompt helps the model reason. It does not decide whether the service may be
restarted.

The distinction only looks pedantic until the first real incident.

## The Instance owns the conversation, not the provider process

Streaming in `0.3.2` requires an Agent Instance. It is the local owner of the
`AgentRef + Subject` pair, retained Runs, and canonical state.

For this example, we also enable observational Receipts:

~~~elixir
children = [
  {Spectre.Supervisor, name: MyApp.SpectreSupervisor},
  {Spectre.Receipt.Sink.Memory, name: MyApp.IncidentReceipts}
]

subject = Spectre.Subject.new({:incident, "INC-742"})

{:ok, instance} =
  Spectre.ensure_instance(
    MyApp.SpectreSupervisor,
    MyApp.IncidentAnalyst,
    subject,
    receipt_mode: :observational,
    receipt_sink:
      {Spectre.Receipt.Sink.Memory, server: MyApp.IncidentReceipts},
    max_stream_sessions: 2,
    idle: :timer.minutes(15)
  )
~~~

The in-memory sink is fine for a demo and for tests. It is not a production
choice. Later we will see what changes with required Receipts and durable
storage.

When inference starts, the Instance commits model selection and dispatch
intent. The provider attempt runs outside its mailbox. This prevents model
latency from turning the state owner into a process that cannot receive
controls.

The provider may be slow. The Instance must not become deaf.

## Open a stream with real limits

Transport lives in a package or module implementing
[`Spectre.Inference.StreamAdapter`](https://github.com/elchemista/spectre/blob/0.3.2/docs/STREAMING_INFERENCE.md).
Core owns lifecycle and limits, not the provider-specific HTTP client.

~~~elixir
{:ok, stream} =
  Spectre.stream(
    instance,
    "Analyze incident INC-742 and explain the most likely cause.",
    plan_actions?: false,
    stream_adapter: MyApp.StreamAdapter,
    stream_adapter_opts: [profile: :fast],
    inference_budget: [
      input_tokens: 12_000,
      output_tokens: 2_000,
      total_tokens: 14_000,
      attempts: 2,
      duration_ms: 120_000
    ],
    stream_provider_stall_timeout: 15_000,
    stream_max_duration_ms: 120_000,
    stream_result_timeout: 30_000
  )
~~~

In `0.3.2`, streaming intentionally supports text generation without Action
planning or structured output. `plan_actions?: false` is not a magic formula
to copy. It declares that this path is producing analysis, not authority over
the outside world.

A hard cost budget would also require an immutable pricing ref and
authoritative cost usage declared by the adapter. Spectre does not turn an
optimistic estimate into accounting just because the number looks precise.

## A delta is not the Agent response yet

The stream is a pull-driven, one-shot Enumerable. A consumer can handle it
like this:

~~~elixir
Enum.each(stream, fn
  %Spectre.Inference.StreamEvent{kind: :delta, payload: text} ->
    MyApp.IncidentUI.render_provisional(text)

  %Spectre.Inference.StreamEvent{kind: :usage, usage: usage} ->
    MyApp.IncidentUI.update_meter(usage)

  %Spectre.Inference.StreamEvent{kind: :inference_completed} ->
    MyApp.IncidentUI.mark_provider_complete()

  %Spectre.Inference.StreamEvent{
    kind: :result,
    payload: %Spectre.Result{} = result
  } ->
    MyApp.IncidentUI.deliver_committed(result)

  %Spectre.Inference.StreamEvent{kind: kind}
  when kind in [
         :failed,
         :cancelled,
         :ambiguous,
         :interrupted,
         :superseded
       ] ->
    MyApp.IncidentUI.mark_terminal(kind)
end)
~~~

The important distinction is between `:delta` and `:result`.

A delta is provisional text. It has crossed incremental screening, but not
normal complete post-processing and not the final Run commit. It must not be
stored as an authoritative answer, sent by email, or used to activate an
Effect.

The `:result` contains the canonical `%Spectre.Result{}`. The provider has
finished, the complete response has crossed the controls, and the Run has been
committed.

Concatenating deltas to reconstruct the result is incorrect. The incremental
sanitizer may suppress more text than the terminal sanitizer, for example when
a control marker crosses two UTF-8 chunks. The safety relation goes in one
direction: the provisional lane may show less, never more than the complete
control would permit.

If only the canonical result matters, enumeration is unnecessary:

~~~elixir
{:ok, %Spectre.Result{} = result} =
  Spectre.await_result(stream, 60_000)
~~~

Streaming remains useful to the UI. The result remains useful to the system.
Confusing them is convenient until it matters.

## Steering does not rewrite the past

During the analysis, the operator narrows the problem:

~~~elixir
{:ok, replacement} =
  Spectre.Inference.Stream.steer(
    stream,
    "Focus only on payment timeouts after deploy checkout-1842."
  )
~~~

The old Enumerable terminates with `:superseded`. It does not suddenly start
emitting events belonging to the replacement. The new handle has another
stream epoch and another Invocation and must be consumed explicitly.

This detail removes a classic generative interface bug: text produced under
different instructions presented as one answer.

The handle also contains a live bearer token. Its `Inspect` implementation
hides it, but that does not make it a durable object. It may remain in the
local state of an authorized process. It must not enter a database, log,
PubSub message, or payload sent to the browser.

The operator may change direction. The operator cannot retroactively rewrite
which intent generated the tokens already produced.

## Backpressure means before the mailbox

Many systems claim backpressure because they keep a bounded queue after
receiving unbounded data. That is a comforting sentence, not a property.

Spectre prefers pull adapters. StreamSession grants transport at most one
credit at a time. A push adapter is accepted only if it declares
`:bounded_push_transport` and applies a real limit before messages enter the
mailbox.

Core limits duration, attachment, provider stall, consumer inactivity, delta
size, accumulated response size, and queued events and bytes. The adapter owns
the two limits that Core can no longer see after parsing: raw chunk size and
parser residual size.

This separation matters. Spectre can verify its own boundary. It cannot
pretend to control the socket of an HTTP library that applies no flow control.

## A crash does not authorize a creative retry

Suppose the Instance dies after dispatch. The provider may still be working,
may have completed, or may have charged the request. The absence of a local
result does not prove that the external work did not happen.

During recovery, Spectre observes what it can prove:

| Available evidence | Behavior |
| --- | --- |
| The provider has not started | Dispatch may safely begin |
| A durable cursor exists and the adapter supports `:resume` | A successor Invocation is committed with a new epoch |
| A stable request id exists and the adapter supports `:reconcile` | The adapter classifies the uncertain work |
| Sufficient evidence does not exist | The Run ends as `:interrupted` or `:ambiguous` |

The old handle does not change in place. If recovery created a successor, the
owner can request it by presenting the old handle as correlated proof:

~~~elixir
{:ok, replacement} = Spectre.resume_stream(instance, old_stream)
~~~

The system prefers explicit ambiguity to a hidden second charge. It is less
magical and much cheaper.

## The human returns when authority changes

Analysis may advance autonomously inside its budget and Definition. Restarting
a service is different.

When the operator writes `restart checkout`, the route does not use the
previous stream as authorization. It opens a normal Turn, prepares the
`restart_checkout` Effect, and encounters `:restart_confirmation`. Only a
response satisfying the declared Policy can approve it. The host application
must then execute the real capability separately and use the idempotency key
at its durable boundary.

This is the useful form of human in the loop.

The human does not validate every token. The human decides when the system
requests new authority. Code decides when that request is mandatory.

For model-selected Actions, `0.3.2` also adds validation of a bounded JSON
Schema subset at both planning and execution boundaries. A malformed argument
does not become more credible after human approval.

## Receipts: evidence, not exactly-once mythology

[`Boundary Receipts`](https://github.com/elchemista/spectre/blob/0.3.2/docs/RECEIPTS.md)
are optional. In `:observational` mode, they are appended
after the canonical commit and a sink failure does not block the Run. In
`:required` mode, Spectre uses a checkpointed outbox and imposes a barrier
before crossing the configured boundary.

Required mode needs a real durable Checkpoint Store and a
`Spectre.Receipt.Sink` capable of preserving content-addressed payloads. The
in-memory sink in the example does not satisfy that operational
responsibility.

A `Spectre.Receipt.Envelope` binds typed evidence to the Definition, closure,
and canonical pre and post roots. It redacts constitutionally sensitive keys
before calculating the digest. It does not expose credentials, cursors, raw
provider errors, or public request ids.

But a Receipt does not prove deterministic replay. It does not prove
exactly-once provider work. It does not prove exactly-once execution of an
external Effect. It proves that specific evidence is bound to a specific
boundary and specific state.

That is already substantial. Calling it more than that would make it less
useful, not stronger.

## Which problems Spectre actually closes

We can now return to the opening paradox without turning it into marketing.

| Concern | Boundary provided by Spectre |
| --- | --- |
| A human must watch every iteration | Policies, budgets, and named controls move intervention to changes in authority or intent |
| The model produces late or duplicate output | Fencing across generation, Run, Invocation, dispatch, epoch, and sequence rejects stale events |
| A correction while running mixes two requests | Steering replaces the attempt and terminates the old one as `:superseded` |
| The UI treats tokens as truth | Provisional deltas and the canonical Result have different events and semantics |
| Costs and loops grow without a ceiling | Aggregate budgets, deadlines, capacity, and buffers are finite |
| A crash invites repetition of uncertain work | Resume and reconcile require provider evidence, otherwise the outcome remains explicit |
| We cannot tell which state crossed a boundary | Optional Receipts bind evidence to canonical pre and post roots |
| Rules change together with the prompt | Definitions, Actions, Policies, and authority remain verifiable code and data structures |

Spectre does not remove human judgment. It gives that judgment an address.

## What Spectre does not close for the application

An honest runtime must also declare where it ends.

Spectre does not automatically create task-scoped OAuth credentials. It does
not decide database RBAC. It does not make an overly broad administrative
token safe. It does not transform an ordinary container into a kernel-isolated
sandbox. It cannot guarantee the durability of an adapter that lies, and it
cannot impose backpressure on an HTTP client that already filled a mailbox.

Those responsibilities belong to the host, deployment, or specialized
packages. Spectre provides places to apply them: the Authority Envelope,
Action and Effect boundaries, Policy, Checkpoint Store, Receipt Sink,
StreamAdapter, and closed operation registry.

The difference is subtle but decisive. An explicit boundary does not solve
security by itself. It makes security possible to implement and test without
asking the model to remember it.

## The loop belongs to the system

Autonomy does not mean the absence of control. It means control has been
transformed from continuous human attention into verifiable structure.

With Spectre `0.3.2`, an inference has an owner, identity, budget, and terminal
state. A stream can be observed without being mistaken for truth. An operator
can change direction without merging two attempts. A crash preserves
ambiguity instead of hiding it behind a retry. A sensitive Effect returns to
the human because a Policy requires it, not because someone happened to be
watching the console.

The model can perform the cognitive work.

The human governs changes in intent and authority.

The runtime owns the loop.
