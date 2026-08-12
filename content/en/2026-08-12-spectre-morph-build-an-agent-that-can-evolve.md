---
title: "Spectre Morph: Build an Agent That Can Evolve Without Rewriting Itself"
slug: "spectre-morph-build-an-agent-that-can-evolve"
lang: "en"
status: published
date: 2026-08-12
updated: 2026-08-12
category: "Software Development"
tags: ["Elixir","OTP","AI agents","Spectre","Morph","runtime skills","governed evolution"]
seo_title: "Spectre Morph: Build a Self-Modifying Elixir Agent"
seo_description: "Learn how Spectre 0.3.0 Morph lets an Elixir agent propose, evaluate and activate runtime Skills through chat or admin without gaining code or authority."
cover_alt: "A Spectre Agent moving from immutable Definition A to evaluated Definition B through a governed Morph proposal"
---

“A self-modifying agent” usually brings the wrong picture to mind.

It sounds like a model opening its own source files, rewriting a prompt, adding a tool, and restarting itself with more power than it had a moment ago. That is certainly modification. It is also a difficult system to audit, reproduce, or trust.

Spectre 0.3.0 takes a different route. An Agent may participate in changing its future behaviour, but it never mutates its running module and it never turns generated text into executable code. It produces — or helps a host produce — a bounded proposal for a **new immutable Definition**. That proposal is evaluated, reviewed, approved, and activated through the same governance path as any other change.

This is what `Spectre.Morph` is for.

The important idea is not that an agent can change. Many systems can change. The important idea is that the agent can change **without becoming the authority that decides whether its own change is safe**.

## Install the released version

Spectre 0.3.0 is available from [Hex](https://hex.pm/packages/spectre/0.3.0), with the public Morph API on [HexDocs](https://hexdocs.pm/spectre/0.3.0/Spectre.Morph.html):

```elixir
def deps do
  [
    {:spectre, "~> 0.3.0"}
  ]
end
```

Morph is part of the core package. It is not a separate plugin and it does not introduce a second runtime beside Spectre.

## What actually changes?

The module written with `use Spectre.Agent` is the compiled definition from which the first canonical Definition is published. A living `Spectre.Instance` owns the ordered runtime state for one Agent and one Subject.

Morph does not edit either of them in place.

Instead, the lifecycle looks like this:

```text
active Definition A
        │
        ▼
     proposal
        │
        ▼
evaluate Candidate B
        │
        ▼
 review and approval
        │
        ▼
activate Definition B
```

Definition A remains in the Definition Store. Definition B has a different content identity and records its lineage. Runs already admitted under A remain pinned to A; new turns admitted after activation may use B. A restart reloads and verifies the durable Activation instead of trusting transient memory.

This is closer to deploying a new immutable release than to changing fields on a chatbot object.

Here is the vocabulary that makes the rest of the article easier to follow:

| Concept | Meaning |
| --- | --- |
| `Agent` module | The compiled, readable declaration owned by the developer |
| `Definition` | The canonical, content-addressed description of behaviour |
| Morph `Surface` | The immutable ceiling describing which changes may be proposed |
| `Change` | An inspectable draft moving through the Morph lifecycle |
| `Candidate` | A possible next Definition, stored with evidence and lineage |
| `Activation` | The explicit, generation-fenced selection of a Candidate for future work |
| Runtime `Skill` | Data-only behaviour mounted inside a new Definition |

## The Agent declares how it is allowed to evolve

Morph is opt-in. An Agent without a `morph` declaration has no Morph door.

Let us build a small support Agent:

```elixir
defmodule MyApp.SupportReplies do
  def render(:help, _input, _context) do
    "I can answer support questions. Type the exact topic you need."
  end
end

defmodule MyApp.SupportAgent do
  use Spectre.Agent, id: :support_agent, history: 30

  router(via: [:regex], semantic_cache?: false, classification_log?: false)

  morph(
    may_propose: [:mount_skill, :replace_skill, :disable_skill],
    within: [scopes: [:support], prompt_tokens: 512],
    approval: :human
  )

  flow :compiled do
    on :HELP, regex: ~r/^help$/i do
      reply(:help, renderer: {MyApp.SupportReplies, :render})
    end
  end
end
```

The `morph` block is not a permission granted to the model. It becomes a must-understand component of the Agent's canonical Definition.

Each option has a precise role:

- `may_propose` is a closed vocabulary. In 0.3.0 Morph accepts mounting, replacing, and disabling runtime Skills.
- `within.scopes` is the largest scope a proposal may use. A caller can select less, never more.
- `within.prompt_tokens` is the maximum prompt budget available to the proposed Skills.
- `approval: :human` means a named human actor must approve the evaluated Candidate.

This declaration is a **ceiling**, not an authority grant. The effective result is still intersected with the host Manifest, Authority Envelope, registered capabilities, prompt budget, and governance policy. If one layer is narrower, the narrower limit wins.

The compiled Agent therefore remains the constitution of the evolving system. Runtime behaviour may fill a space that code deliberately opened; runtime data cannot enlarge that space.

## How “auto-evolution” works in the DSL

`use Spectre.Agent` imports the `morph/1` macro. The macro runs when the Agent module is compiled; it does not start an autonomous learning loop.

The declaration may appear only once. `within:` must contain at least one scope and a positive prompt-token ceiling; `approval:` accepts only `:human` or `:host_policy`; unknown keys and unsupported mutation types fail while compiling the Agent. The runtime therefore cannot reinterpret a loose configuration later.

Its job is to turn the authoring declaration into a canonical `change_surface` component similar to this transport data:

```elixir
%{
  "operation_types" => ["disable_skill", "mount_skill", "replace_skill"],
  "scope_ceiling" => ["support"],
  "prompt_token_ceiling" => 512,
  "approval_requirement" => "human"
}
```

That component is marked `must_understand` and sealed into the Definition's content identity. Changing the DSL produces a different Definition. Runtime input cannot rewrite the Surface, add a fourth operation, raise the token ceiling, or turn human approval into automatic approval.

The DSL therefore defines **how the Agent is allowed to evolve**, while a runtime workflow decides **when to propose an evolution**.

A useful way to separate the levels is:

| Level | May be automated? | Owner |
| --- | --- | --- |
| Observe a problem | Yes, through explicit Experience, metrics, or host events | Host and observation adapters |
| Produce a proposal | Yes, through chat extraction, application logic, or Forge | Agent/model may propose bounded data |
| Evaluate the Candidate | Yes, with the protected corpus and registered checkers | Spectre governance plus host evidence |
| Approve the Candidate | Only as allowed by the declared Surface and stricter risk policy | Human or trusted host policy, never the Agent |
| Activate the Candidate | May be orchestrated by trusted host code, but remains a separate explicit commit | Host through the Instance boundary |

For a chat-trained or admin-managed Agent, use the human ceiling shown above:

```elixir
morph(
  may_propose: [:mount_skill, :replace_skill, :disable_skill],
  within: [scopes: [:support], prompt_tokens: 512],
  approval: :human
)
```

For a tightly controlled system, the DSL can instead allow a trusted host policy to approve changes that its independent risk rules classify as eligible:

```elixir
morph(
  may_propose: [:mount_skill],
  within: [scopes: [:support], prompt_tokens: 128],
  approval: :host_policy
)
```

`approval: :host_policy` does **not** mean “the Agent approves itself.” It means the Agent's Definition does not require a human for every proposal, so trusted host policy may choose human or automatic approval. The independent governance risk policy remains authoritative and may still require a human. Approval still does not activate the Candidate.

Consequently, “automatic evolution” in Spectre is not one magical switch. It is an application pipeline assembled from explicit planes:

```text
Experience or chat
        │
        ▼
Reflection / host inspection
        │
        ▼
bounded Morph or Forge proposal
        │
        ▼
evaluation against protected behaviour
        │
        ▼
human or host-policy approval
        │
        ▼
explicit host activation
```

You may automate the first half heavily. The constitutional boundaries stay visible and independently owned. That is what makes it evolution rather than hidden prompt drift.

## What kind of Skill can Morph create in 0.3.0?

The convenient `Spectre.Morph.mount_skill/3` API creates a deliberately small, reply-only runtime Skill.

It accepts:

- a stable mount id;
- one non-empty exact match;
- a reply fragment;
- optional negative examples through `never:`;
- an optional version;
- a token cap; and
- an explicit subset of the Surface scopes.

The only supported reply placeholder is `{{input.text}}`.

That limitation matters. This is valid:

```elixir
Spectre.Morph.mount_skill(change, "refunds",
  match: {:exact, "refund"},
  reply: "Refund policy applies to: {{input.text}}",
  scopes: [:support],
  token_cap: 128
)
```

This is not a way to inject an Elixir callback, an EEx template, a module name, credentials, or arbitrary code. Morph also cannot use this facade to replace a compiled Skill. `replace_skill/3` and `disable_skill/2` apply only to runtime-origin Skills already present in the active Definition.

Lower-level governed Definitions can reference operations already registered by trusted host code, but runtime data still cannot invent an executor. The 0.3.0 Morph facade stays narrower: it is an ergonomic, reply-only path over the existing governance engine.

## The Morph lifecycle, one boundary at a time

A complete change passes through separate stages:

```elixir
change =
  instance
  |> Spectre.Morph.change(
    by: "actor:author",
    reason: "Teach the support Agent about refunds"
  )
  |> Spectre.Morph.mount_skill("refunds",
    match: {:exact, "refund"},
    reply: "Refund policy applies to: {{input.text}}",
    scopes: [:support],
    token_cap: 128
  )
  |> Spectre.Morph.evaluate(cases: protected_cases)

{:ok, report} = Spectre.Morph.explain(change)

approved =
  Spectre.Morph.approve(change,
    by: "actor:reviewer",
    mode: :human
  )

{:ok, activation} = Spectre.Morph.activate(approved)
```

These calls are intentionally not collapsed into `learn_and_restart/1`.

### 1. `change`

`change/2` opens a draft against the Instance's exact active Definition. The author, reason, and optional evidence are bound to the proposal. The canonical Surface is read from the Definition Store, not trusted from caller state.

### 2. `mount_skill`, `replace_skill`, or `disable_skill`

These functions add typed, inert operations to the draft. They do not modify the running Agent. Invalid options fail the `Change` without partially applying behaviour.

### 3. `evaluate`

Evaluation composes a Candidate and runs real behavioural checks. It compares the parent and Candidate on a protected corpus and adds obligations derived from the actual Definition diff.

For a new exact-reply Skill, Morph creates a Candidate-owned case that proves the new input produces the exact promised output. That case must pass, but it has zero weight in the protected score. A Candidate cannot write easy tests for itself and use them to hide a regression — the classic Goodhart failure.

### 4. `explain`

`explain/1` returns a deterministic human report. It is suitable for an admin page, an audit log, or a chat review card. The report describes verified evidence; it does not ask another model for an ungrounded opinion.

### 5. `approve` or `reject`

Approval is a separate host commit. It records that an authorized actor accepted the evaluated Candidate. It does not make the Candidate active.

### 6. `activate`

Activation rereads the durable artifacts, repeats constitutional verification, and uses the Instance activation generation as a compare-and-swap fence. A stale proposal does not silently overwrite a newer Definition.

This preserves one of Spectre's central rules:

> **Approval is not execution, and a proposal is not authority.**

## The protected corpus is the memory of what must not break

Before enabling Morph, define behavioural cases for the Agent you already trust:

```elixir
protected_cases = [
  %{
    "id" => "unrelated-input-stays-unhandled",
    "input" => "weather",
    "expected_outcome" => "clarify",
    "context" => %{"scope" => "support"},
    "llm" => "forbidden"
  }
]
```

In a real application this corpus should cover important compiled routes, policy boundaries, negative routing cases, and behaviour that must remain unavailable. Its complete canonical content — not only the case ids — is bound into evaluation and closure identity.

If the new `refund` Skill accidentally captures `weather`, collides with an existing route, exceeds its prompt budget, or changes protected behaviour, the Candidate is rejected before activation.

An agent that can evolve without regression tests is merely an agent that can drift.

## Chat and admin are two interfaces, not two security modes

There is no `mode: :chat` or `mode: :admin` inside Morph. This is deliberate.

Chat and an admin panel are application entry points. They may collect the same proposal differently, but both must pass through the same host-owned Morph pipeline.

| Question | Chat interface | Admin interface |
| --- | --- | --- |
| How is intent collected? | A conversation, optionally structured by a model | A typed form or internal API |
| Who authenticates the actor? | The host behind the channel | The host behind the admin session |
| Who supplies `by:` and approval mode? | Trusted host code | Trusted host code |
| Can input widen the Surface? | No | No |
| Can it activate without evaluation? | No | No |
| Does it create the same Candidate lineage? | Yes | Yes |

This distinction lets you build two pleasant experiences without creating two governance systems.

## Put the shared Morph logic in normal Elixir

The application should own one service that both interfaces call:

```elixir
defmodule MyApp.AgentEvolution do
  alias Spectre.Morph

  def propose(instance, actor_ref, reason, skill, protected_cases) do
    change =
      instance
      |> Morph.change(
        by: actor_ref,
        reason: reason,
        evidence: Map.get(skill, :evidence, %{})
      )
      |> Morph.mount_skill(skill.mount_id,
        match: {:exact, skill.match},
        reply: skill.reply,
        scopes: skill.scopes,
        token_cap: skill.token_cap
      )
      |> Morph.evaluate(cases: protected_cases)

    case Morph.status(change) do
      %{state: :evaluated, error: nil, candidate_ref: candidate_ref} ->
        with {:ok, report} <- Morph.explain(change) do
          {:ok, %{candidate_ref: candidate_ref, report: report}}
        end

      status ->
        {:error, status}
    end
  end

  def approve_and_activate(instance, candidate_ref, reviewer_ref) do
    approved =
      instance
      |> Morph.resume(candidate_ref, by: reviewer_ref)
      |> Morph.approve(by: reviewer_ref, mode: :human)

    case Morph.status(approved) do
      %{state: :approved, error: nil} -> Morph.activate(approved)
      status -> {:error, status}
    end
  end
end
```

Production code should log the status projection, retain the report and evidence, and handle rejected or stale Candidates explicitly. The example keeps the happy path visible without moving policy into a controller or prompt.

The `instance` in this example must already have an active canonical Definition and a configured Definition Store. Its Manifest must grant the corresponding runtime Skill capabilities and prompt budget. For a durable deployment, the Instance also needs the normal durable checkpoint and ownership setup described in the Spectre operations documentation.

## Mode 1: propose a new Skill through chat

Suppose an authenticated operator tells the Agent:

> When somebody writes exactly “refund”, answer that the refund policy applies to their request.

A model may help translate that sentence into a closed intent:

```elixir
skill_intent = %{
  mount_id: "refunds",
  match: "refund",
  reply: "Refund policy applies to: {{input.text}}",
  scopes: [:support],
  token_cap: 128,
  evidence: %{
    "source" => "chat",
    "conversation_id" => conversation.id
  }
}
```

The model output is not passed through as arbitrary options. The host validates this fixed schema, derives the authenticated actor itself, and calls the shared service:

```elixir
{:ok, pending} =
  MyApp.AgentEvolution.propose(
    instance,
    "operator:#{current_user.id}",
    "New support behaviour requested in chat",
    skill_intent,
    protected_cases
  )

send_review_card(pending.candidate_ref, pending.report)
```

At this point the Agent has **proposed** a new Skill. It has not installed one.

An authenticated reviewer may approve from the same chat experience, but the application must resolve that identity and render an explicit confirmation. The model must never be allowed to emit its own `by:`, choose `mode: :human`, or call activation because it wrote the word “approved”.

```elixir
{:ok, activation} =
  MyApp.AgentEvolution.approve_and_activate(
    instance,
    pending.candidate_ref,
    "reviewer:#{current_admin.id}"
  )
```

The chat is therefore a conversational proposal and review UI. It is not the security boundary.

## Mode 2: create and approve a Skill from an admin panel

The admin flow does not need a model at all. A LiveView form can collect:

- mount id;
- exact trigger;
- reply text;
- allowed scope; and
- token cap.

The form submits the same `skill_intent` shape to `MyApp.AgentEvolution.propose/5`. The admin page renders `pending.report`, shows the parent and Candidate refs, and exposes separate **Reject** and **Approve and activate** actions.

```elixir
{:ok, pending} =
  MyApp.AgentEvolution.propose(
    instance,
    "admin:#{author.id}",
    "Add the refund answer from the support console",
    skill_intent,
    protected_cases
  )

# Render pending.report and require an explicit second action.

{:ok, activation} =
  MyApp.AgentEvolution.approve_and_activate(
    instance,
    pending.candidate_ref,
    "reviewer:#{reviewer.id}"
  )
```

Spectre requires a named human for a Surface declared with `approval: :human`; whether your product additionally requires the author and reviewer to be different people is a host policy decision. For important agents, separation of duties is worth enforcing.

## Prove that the Agent actually changed

Before activation, the new route is not active:

```elixir
{:ok, before_turn} =
  Spectre.turn(instance, "refund",
    skill_context: %{"scope" => "support"}
  )

{:no_response, _result} = before_turn.decision
```

After approval and activation, a fresh turn resolves through the runtime Skill:

```elixir
{:ok, after_turn} =
  Spectre.turn(instance, "refund",
    skill_context: %{"scope" => "support"}
  )

{:reply, "Refund policy applies to: refund", _turn_ref} =
  after_turn.observable
```

`skill_context` must come from trusted host context. Do not derive a privileged scope from arbitrary user text. With several scopes in a Surface, Morph also requires each proposed Skill to select an explicit non-empty subset rather than inheriting broad access by omission.

## Replace or disable what Morph created

The same lifecycle can improve a runtime Skill:

```elixir
change =
  instance
  |> Spectre.Morph.change(
    by: "operator:author",
    reason: "Clarify the refund answer"
  )
  |> Spectre.Morph.replace_skill("refunds",
    match: "refund",
    reply: "A support specialist will review: {{input.text}}",
    scopes: [:support],
    token_cap: 128
  )
  |> Spectre.Morph.evaluate(cases: protected_cases)
```

Or withdraw it:

```elixir
change =
  instance
  |> Spectre.Morph.change(
    by: "operator:author",
    reason: "Withdraw the obsolete refund answer"
  )
  |> Spectre.Morph.disable_skill("refunds")
  |> Spectre.Morph.evaluate(cases: protected_cases)
```

Both still require review, approval, and activation. Disable evaluation also checks that removing the Skill does not cause its input to be captured unexpectedly in a sibling scope.

## Stale proposals and rollback are explicit

Imagine two proposals are opened from Definition A. The first activates Definition B. The second proposal still points at A and is now stale.

Spectre does not silently replay it on B. You must choose to rebase its typed intent:

```elixir
rebased =
  stale_change
  |> Spectre.Morph.rebase(
    by: "operator:author",
    reason: "Rebase the proposal on the current Definition"
  )
  |> Spectre.Morph.evaluate(cases: protected_cases)
```

Rebase creates a new identity and reruns the checks.

Rollback is also explicit and forward-moving. Spectre activates an immutable ancestor as a new activation generation; it does not erase Definition B and it does not pretend to undo external Effects already performed while B was active.

That is a subtle but important distributed-systems truth: code state can move back, while the outside world may not.

## Morph, Reflection, and Forge are different things

Spectre 0.3.0 also introduces Reflection, Experience, and Forge. They complement Morph, but they are not aliases for it.

| Plane | Purpose | What it cannot do |
| --- | --- | --- |
| Experience | Record explicit, redacted observations | Become authority or canonical state by itself |
| Reflection | Mechanically inspect declared, effective, and observed facts | Execute inspected instructions or call a model |
| Forge | Produce an inert proposal from verified Reflection and Experience | Publish, approve, activate, or register code |
| Morph | Give the host a small API for governed Skill changes | Widen the Agent Surface or bypass governance |

A future chat experience may use Reflection and a model-backed Forge critic to suggest that a Skill is missing. The final suggestion is still a proposal. The same Store-backed evaluation, approval, and activation chain remains in control.

## What Morph deliberately refuses to be

Morph is not:

- a prompt that tells a model to improve itself;
- a dynamic Elixir compiler;
- a mechanism for downloading and executing generated Skills;
- an unbounded tool registry;
- memory disguised as behaviour;
- proof that a model's proposal is correct; or
- permission for an Agent to approve its own change.

These refusals are the feature.

They preserve the broader Spectre philosophy:

1. **The model proposes; the host executes.**
2. **Runtime data never becomes code.**
3. **Definitions are immutable and content-addressed.**
4. **One OTP Instance owns ordered canonical mutation.**
5. **Runs keep the Definition that admitted them.**
6. **Approval and activation are separate facts.**
7. **Missing evidence, ambiguity, and stale state fail closed.**

## A production checklist

Before exposing Morph through chat or an admin panel, make sure the application has:

- an authenticated, host-derived actor identity;
- a durable Definition Store and the normal Instance persistence boundary;
- the narrowest possible Morph Surface;
- a protected corpus that covers existing positive and negative behaviour;
- explicit runtime Skill capabilities in the Manifest authority;
- prompt budgets smaller than the Agent's kernel reserve;
- review UI based on `Morph.explain/1` and `Morph.status/1`;
- separate rejection, approval, and activation handling;
- explicit rebase for stale proposals;
- retained lineage and audit evidence; and
- a rollback plan that does not claim to reverse external side effects.

Also test a real turn before and after activation. Constructing a valid `Change` proves only that a proposal is well shaped; it does not prove that the living Agent behaves as intended.

## The real meaning of a self-modifying Spectre Agent

A Spectre Agent does not become a little developer with shell access.

It becomes a system capable of proposing a new version of its own declared behaviour while remaining inside limits chosen by code, authority chosen by the host, evidence chosen by evaluation, and ownership enforced by an OTP process.

Chat can make that evolution conversational. An admin panel can make it operational. Reflection and Forge can make proposals better informed. None of those interfaces changes the constitutional path.

That is why Morph fits Spectre instead of weakening its philosophy: **the Agent may evolve, but the rules by which it evolves do not belong to the Agent.**
