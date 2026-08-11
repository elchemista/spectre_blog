---
title: "A Turn Is Not a Model Call: How Spectre Governs Agents with OTP"
slug: "a-turn-is-not-a-model-call-spectre-otp-policies"
lang: "en"
status: published
date: 2026-08-11
updated: 2026-08-11
category: "Software Development"
tags: ["Elixir","OTP","Actor Model","AI agents","Spectre","agent governance","policy"]
seo_title: "Spectre Turns, Policies and OTP Agent Governance"
seo_description: "Why Spectre defines a turn as an observable runtime boundary, uses deterministic policies for protected effects, and builds agent ownership on Actors and OTP."
cover_alt: "A subject-scoped Spectre actor advancing a run to a visible turn boundary, with a deterministic policy separating proposed, approved, and executed effects"
---

In many agent frameworks, a turn begins when input reaches a model and ends when the model has finished calling tools and produced an answer.

I started Spectre from a different question:

> **At which point does responsibility move from the agent runtime to the application that owns the real world?**

That question changed the meaning of a turn.

In Spectre, a `Turn` is not a synonym for one LLM request, one pass through a graph or one complete tool loop. It is the public projection produced when a recoverable `Run` reaches its first observable boundary. The boundary may be a reply, a policy request or an external invocation. The model may have participated before that point, or no model may have been called at all.

The useful sentence is:

> **A Spectre Turn ends when the owner of the next decision changes.**

If the runtime has text to expose, the host owns delivery. If a protected effect needs approval, a person or trusted host owns that decision. If an approved capability must run, an executor outside the reasoning loop owns the side effect. Spectre does not hide those transfers behind another automatic iteration.

This is one of the main ways Spectre differs from more model-first agent frameworks, and it comes directly from the Actor Model, OTP and the less glamorous parts of distributed systems.

## The Actor Model was the starting point

The module that uses `Spectre.Agent` is not a living actor. It is the compiled definition of behaviour.

The living runtime object is a subject-scoped `Spectre.Instance`:

```text
AgentRef + Subject → one logical Instance
```

An Instance owns the ordered state of the relationship between one logical agent and one canonical subject. It has a mailbox, serializes accepted state changes and retains the Runs that belong to that subject. A PID may disappear after a crash; the logical identity does not have to disappear with it.

This maps naturally onto ideas I learned from actors and OTP:

| Actor or OTP idea | Spectre interpretation |
| --- | --- |
| One process owns its state | One Instance owns the canonical state for `AgentRef + Subject` |
| Other participants communicate by messages | Run moves, worker results and control commands return to the Instance as correlated messages |
| A mailbox gives order | State-changing moves are accepted serially instead of racing over shared mutable state |
| Process identity is not business identity | The PID is temporary; `AgentRef + Subject` is the stable address |
| Slow or failing work should be isolated | Capability and operation runners work outside the Instance mailbox |
| Supervisors rebuild processes | OTP restarts the runtime process; configured checkpoints restore durable state |
| Failure is expected | Revisions, fencing and idempotency decide whether a late result is still valid |

I did not copy the Actor Model as an aesthetic. I used it to answer ownership questions.

Who is allowed to mutate this state? Which Run owns this pending confirmation? What happens if an external action returns after the agent has advanced? Can a second process apply the same receipt? Those questions become much easier when there is one canonical owner and everything else must return evidence to it.

OTP supervision is important, but “let it crash” is not enough. A restarted process can be rebuilt. A duplicated payment, deleted record or published article cannot be undone by a supervisor. Spectre therefore combines failure isolation with revision fences, stable effect identifiers, idempotency keys and explicit ambiguous outcomes.

A crash is expected. It is not proof that nothing happened.

## What one Turn actually does

The public entry point is deliberately small:

```elixir
{:ok, turn} = Spectre.turn(instance, input)

case turn.observable do
  {:reply, output, run_ref} ->
    deliver_once(output, Spectre.Run.Ref.token(run_ref))

  {:needs, policy_boundary} ->
    present_policy(policy_boundary)

  {:awaiting, invocation_ref} ->
    dispatch_invocation(turn.boundary, invocation_ref)
end
```

Internally, much more can happen:

```text
normalise input
  → restore state and recall memory
  → resume an open policy, or route a normal turn
  → run deterministic code and optional model reasoning
  → stage a reply or Effect
  → commit authoritative state
  → stop at the first observable boundary
```

The closed observable vocabulary matters. A browser integration, payment adapter or future agent-to-agent transport does not get to invent a new kind of Turn. Extensions may add new Effect kinds, but the host still sees the same lifecycle boundary.

The continuation also remains private. A `Turn` exposes a revision-fenced `Run.Ref`, not the mutable Run itself. The Instance retains the continuation and rejects a stale reference, a foreign invocation or a reply aimed at the wrong Run revision.

That is actor-style encapsulation applied to an agent runtime: the outside world receives an address and a request, not ownership of the machine.

## A Policy is a temporary deterministic router

Here I mean a runtime `Policy` attached to a protected Effect, not a vague instruction in the system prompt and not the broader governance policies used to approve new Definitions.

Consider a destructive action:

```elixir
actions MyApp.AccountActions do
  protect(:delete_account, with: :confirm_delete)
end

policy :confirm_delete do
  request(:confirm_delete_request)
  accept(:confirmed, regex: ~r/^yes,?\s+delete$/iu)
  reject(:cancelled, regex: ~r/^(no|cancel)$/iu)
  otherwise(ask: :confirm_delete_retry)
  attempts(3, then: :cancel_pending)
end

flow :account do
  on :DELETE_ACCOUNT, regex: ~r/^delete my account$/iu, cache: false do
    action(:delete_account)
  end
end
```

The first input does not call `delete_account/2`. It stages an Effect with the status `:waiting_policy` and opens an Awaitable owned by that Run.

While that policy is open, normal routing does not get another chance to reinterpret the next answer. The policy has precedence over turn handlers, classifiers and LLM routing. A pure matcher compares normalized input with the declared accept and reject branches. Unknown text increments an attempt counter. Rejection or exhausted attempts cancels the pending Effect.

This precedence is more important than the regular expression itself.

If the user writes “yes, delete”, I do not want an LLM to decide that this probably means approval while also considering unrelated routes, retrieved documents and tool descriptions. I want the runtime to know that one exact Run is waiting for one exact decision under one compiled policy.

A trusted application can also resolve the policy with a declared label:

```elixir
{:ok, approved_turn} =
  Spectre.Turn.resolve_policy(turn, {:accept, :confirmed})
```

It does not need to manufacture a fake user message such as `"yes"`. The source of the decision is recorded, the label must exist in the policy, and invalid resolutions fail without mutating state.

## Proposed, approved and executed are different facts

Many agent APIs make tool approval available, and that is a good development. Spectre's stronger opinion is that proposal, approval and execution are separate lifecycle facts even when the happy path makes them look like one operation.

| Boundary | Effect state | Has the action run? | Who owns the next step? |
| --- | --- | --- | --- |
| Protected action is selected | `:waiting_policy` | No | Policy resolver |
| Policy accepts | `:approved` | No | Host or capability executor |
| Policy rejects or expires | `:cancelled` | No | Nobody; it is terminal |
| Execution receipt commits | `:completed` or `:failed` | Yes | Runtime records the outcome |

Approval is committed before execution. The external result is committed afterward. If the second commit is uncertain, Spectre returns ambiguity instead of silently deciding that the action should run again.

This resembles a tiny transaction protocol around a capability, although Spectre cannot make an arbitrary external system transactional. The host still has to implement the real action safely and persist the idempotency key with the domain operation.

A Policy is also not a replacement for authorization. Confirmation answers “did the expected actor approve this staged operation?” Authorization still answers “is this authenticated subject allowed to delete this account now?” The host must enforce that at the real capability boundary, using current business data.

This separation is intentionally uncomfortable. It prevents a pleasant chat interaction from being mistaken for authority.

## Ownership matters when several things are open

A long-lived agent does not always have one request in flight.

One Subject may speak through a website and Telegram. A report may be running while another Turn asks for confirmation. Two different protected actions may be awaiting answers. Meanwhile, the agent Definition may be upgraded.

Spectre does not solve this by keeping one enormous model loop alive.

Normally each new input creates a new Run over the Instance's shared, ordered State. A policy response is the important exception: it resumes the Run that owns the Awaitable. The input source identifies its conversation origin, so a plain “yes” can be correlated with the right suspended boundary.

If several policies could own the reply and the origin is missing, Spectre returns an ambiguity error. It does not choose the newest Run, the first list entry or the action that seems semantically closest.

This becomes even more valuable when behaviour changes. In the 0.3 runtime, a Run is pinned to the immutable Definition that admitted it. New input can use Definition B while a confirmation opened by Definition A continues under A. Current authority is still checked before the next Effect, so reproducible old behaviour does not become permanent old permission.

That combination is subtle:

- the Instance preserves one logical identity;
- each Run preserves its semantic owner;
- the active Definition owns new work;
- current authority can still revoke old work;
- the model does not decide which version should receive an event.

This is where Actor ownership grows into agent governance.

## How this differs from other frameworks

Spectre is not the only project with durable execution, human approval, explicit state or OTP processes. Claiming that would be both wrong and strategically useless.

[LangGraph](https://github.com/langchain-ai/langgraph) has durable execution, interrupts, memory and excellent graph-level observability. [Mastra](https://github.com/mastra-ai/mastra) can suspend and resume agents and workflows. [OpenAI Agents SDK](https://github.com/openai/openai-agents-python) provides tools, guardrails, sessions, tracing and human-in-the-loop flows. [PydanticAI](https://github.com/pydantic/pydantic-ai) has type-safe outputs, tool approval and durable execution. [Jido](https://github.com/agentjido/jido) is already an OTP-native Elixir framework with explicit state, Actions, Signals and Directives.

The difference is not a checklist item. It is the object placed at the centre of the runtime.

| Approach | Centre of gravity | What it does especially well | Spectre's different bet |
| --- | --- | --- | --- |
| Model-first SDKs such as OpenAI Agents SDK and PydanticAI | Agent run, model, tools and final output | Fast construction, provider integrations, typed results, guardrails and approvals | A model call is optional inside a Turn; the host receives the first ownership boundary instead of surrendering the lifecycle to a tool loop |
| Graph systems such as LangGraph and Mastra workflows | Graph state, nodes, edges, checkpoints and interrupts | Explicit orchestration, durable workflows and visual execution paths | The primary owner is a subject-scoped actor with multiple Runs; policy and Effect ownership remain runtime invariants rather than merely graph conventions |
| Jido | Immutable agent state, commands, Actions, Signals and runtime Directives | Native Elixir composition, supervision and autonomous distributed workflows | Spectre applies a narrower protected-Effect lifecycle and revision-fenced Turn boundary, with approval and execution kept apart by default |
| Spectre | Identity, ownership, authority and observable boundaries | Governed continuations, deterministic policy precedence and failure-aware effects | It accepts more ceremony and a smaller ecosystem to make the control plane explicit |

For a prototype that needs to call three tools and return an answer, I would not argue that Spectre is automatically the best choice. The lighter path is often the correct one.

Spectre becomes interesting when the agent survives longer than the request, changes behaviour while work remains open, acts across channels, or touches operations for which “the model probably did the right thing” is not an acceptable audit record.

## The other ideas hiding inside Spectre

The Actor Model and OTP are the visible foundation, but several other software ideas shape the runtime.

### State machines instead of conversational implication

An Effect cannot jump directly from `:waiting_policy` to `:completed`. Lifecycle transitions are explicit and invalid transitions are rejected. The chat transcript may explain why something happened; it does not define what states are legal.

### Capability security instead of universal tools

The model does not receive arbitrary application authority. It can select or prepare data for registered operations. An Effect is a description of requested work, not the capability to perform it. The executor and host still own the credential and the final authorization decision.

### Projections instead of leaking continuations

A `Turn` is a projection of a Run at a boundary. A `Result` is a receipt for a transition. The full continuation remains behind the owner. This is similar to the way mature systems expose views and commands without handing clients their internal state machine.

### Distributed-systems pessimism

Timeout does not mean failure. Crash does not mean rollback. A repeated message is not necessarily a new intention. This is why Spectre uses stable identifiers, revision checks, compare-and-swap, idempotency keys and explicit ambiguous outcomes.

### Supervision without magical recovery

OTP can restart an Instance or a failed runner, but durable recovery requires a validated checkpoint and re-resolution of runtime dependencies. PIDs, clients, functions and secrets do not belong inside the continuation. They are resolved again from the deployed application.

These ideas are not fashionable agent features. They are old software lessons applied to a new kind of unreliable participant: a probabilistic model operating inside a stateful application.

## What I think Spectre gets right

The strongest part of Spectre is not that it uses Elixir or that it has a DSL. It is the refusal to let one abstraction own everything.

- The model owns probabilistic interpretation and reasoning.
- The router owns the selection among declared behaviour.
- The Policy owns one deterministic approval boundary.
- The Lifecycle owns legal state transitions.
- The Instance owns canonical subject state and Run scheduling.
- The executor owns the external attempt.
- The host owns identity, authorization, credentials, storage and delivery.

Because those owners are explicit, the runtime can explain where it stopped and what evidence is required to continue.

That does not make Spectre automatically safe. A bad policy can approve the wrong thing. A broad action can expose too much authority. A broken store can lose state. An executor can ignore idempotency. A model can still produce terrible reasoning.

What Spectre does well is make those failures belong to visible components instead of dissolving them into one intelligent loop.

That is also why I do not want Spectre to become a general framework by copying every integration from larger ecosystems. LangGraph, Mastra, OpenAI Agents SDK, PydanticAI and Jido already solve many problems extremely well.

Spectre should own a narrower question:

> **How can an agent receive input, pause, act, fail, restart and evolve without losing the identity and authority of the exact operation in progress?**

The `Turn` and the `Policy` are small answers to that question. OTP is what makes those answers feel less like a chatbot convention and more like a runtime.
