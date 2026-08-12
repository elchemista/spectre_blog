---
title: "Do Not Trust the Model: Test a Spectre Agent Like Software"
slug: "do-not-trust-the-model-test-spectre-agents-like-software"
lang: "en"
status: published
date: 2026-08-12
updated: 2026-08-12
category: "Software Development"
tags: ["Elixir","ExUnit","AI agents","Spectre","testing","OTP","Policy","idempotency"]
seo_title: "Test Spectre Agents Without Trusting the Model"
seo_description: "Learn to test routing, Policies, Effects, crashes, retries, and Morph Candidates in Spectre 0.3.0 by separating deterministic invariants from model evals."
cover_alt: "An ExUnit suite surrounds a probabilistic model and verifies the deterministic boundaries of a Spectre agent"
---

An agent produced the correct answer. The test passes.

But did it call the model three times when none were needed? Did it stage a
destructive action before approval? Did it execute the same operation twice
after a timeout? Did it modify durable state before the commit succeeded?

If the test checks only the final text, it cannot answer any of those
questions.

This is one of the strange problems of agentic software: a correct result can
hide an incorrect, expensive, or dangerous path. A model can reach the desired
sentence after ignoring a Policy. A router can choose the right route while
unnecessarily using an LLM. An executor can return an error after it has
already created a record in an external system.

Spectre's testing philosophy begins here:

> **You do not need to prove that the model will always be trustworthy. You
> need to prove that the runtime will not let it cross verifiable boundaries.**

In Spectre 0.3.0 the model remains probabilistic, but ownership, lifecycle,
Policies, Effects, revisions, and commits are software. They can be tested like
software.

## Tests and evals answer different questions

The first important distinction is between a **contract** and
**probabilistic quality**.

An ExUnit test should answer questions such as:

- does a protected Effect remain non-executable before approval?
- does rejection really prevent the Action callback?
- does an unknown host label leave state unchanged?
- is a crash after commit classified as ambiguous?
- does a retry preserve the same idempotency key?
- does a Session restore pending work after restart?

A router eval answers different questions:

- do these eighty ways of requesting support reach the correct route?
- which ambiguous inputs genuinely require the model?
- has a deterministic route started making unnecessary LLM calls?
- did a prompt or model change reduce the pass rate?

Both are necessary, but they are not interchangeable.

| Layer | What it verifies | Must it be deterministic? |
| --- | --- | --- |
| Unit and contract tests | Transitions, callbacks, state, and authority boundaries | Yes |
| OTP lifecycle tests | Crashes, restarts, recovery, fencing, and replay | Yes |
| Routing evals | Corpus behavior and permitted LLM use | The corpus and thresholds must be; the provider may be fake or real |
| Morph evaluation | Regressions between a parent Definition and Candidate | Gates and receipts must be; live providers stay separate |
| Real-provider tests | Compatibility, latency, and real model or embedding behavior | No; they belong in a separate suite |

If everything is mixed into one online suite, every failure becomes ambiguous.
You no longer know whether a runtime transition broke, a prompt changed, or a
provider returned a different answer.

## Build the smallest interesting Agent

We will use an Agent that can create a project only after a Policy has been
accepted. The Action is ordinary Elixir code and sends a message to the test
process when it is actually invoked:

```elixir
defmodule MyApp.ProjectActions do
  def create_project(args, ctx) do
    if pid = Keyword.get(ctx.opts, :test_pid) do
      send(pid, {:project_created, args})
    end

    {:ok, %{id: "project-123", args: args}}
  end
end

defmodule MyApp.ProjectAgent do
  use Spectre.Agent

  router(via: [:regex])

  input_pipeline do
    plug(Spectre.Input.Plugs.NormalizeText,
      trim?: true,
      case: :downcase
    )
  end

  actions MyApp.ProjectActions do
    protect(:create_project, with: :terms)
  end

  policy :terms do
    accept(:accepted_terms, regex: ~r/^yes$/i)
    reject(:rejected_terms, regex: ~r/^(no|cancel)$/i)
    attempts(2, then: :cancel_pending)
  end

  flow :projects do
    on :START_PROJECT,
      regex: ~r/^start project$/i,
      via: [:regex],
      cache: false do
      action(:create_project, args: %{source: "chat"})
    end
  end
end
```

This Agent does not need a model for the test. We are not simulating
intelligence; we are isolating a contract that must remain true regardless of
which model is mounted later.

## The most important test checks what does not happen

The first Turn stages the intent, but it must stop at the Policy:

```elixir
defmodule MyApp.ProjectAgentTest do
  use ExUnit.Case, async: true

  alias MyApp.ProjectAgent
  alias Spectre.Awaitable
  alias Spectre.Effect
  alias Spectre.Result

  test "a protected Action does not execute before approval" do
    assert {:ok, turn} =
             Spectre.turn(
               ProjectAgent,
               "  START PROJECT  ",
               test_pid: self()
             )

    assert {:awaiting, %Awaitable{name: :terms, status: :open}, result} =
             turn.decision

    assert [%Effect{status: :waiting_policy} = waiting] =
             result.state.pending_effects

    waiting_id = waiting.id

    assert {:error, {:effect_not_approved, ^waiting_id}} =
             execute(result)

    refute_received {:project_created, _args}
  end

  defp execute(%Result{} = result) do
    Spectre.execute(result.state, %{
      agent: ProjectAgent,
      input: result.input,
      state: result.state,
      opts: [test_pid: self()]
    })
  end
end
```

The returned value is only one part of the proof. The decisive line is:

```elixir
refute_received {:project_created, _args}
```

It proves that the capability was not invoked. An assertion on a “Please
confirm” response would not prove that: the Agent could have created the
project and asked for confirmation too late.

A good contract test observes both sides of the boundary:

1. the returned value or process outcome;
2. callbacks invoked with the correct order and cardinality;
3. callbacks that must not be invoked;
4. in-memory and durable state before and after commit; and
5. behavior after retry, replay, or restart.

Coverage tells you which lines were visited. It does not tell you that an
Effect executed exactly once.

## Approval and execution must remain separate proofs

We can now continue the same state with `yes`. The Policy owns this response,
so the normal router must not reinterpret it:

```elixir
test "approval makes the Effect executable but does not execute it" do
  assert {:ok, awaiting_turn} =
           Spectre.turn(
             ProjectAgent,
             "start project",
             test_pid: self()
           )

  assert {:awaiting, _awaitable, awaiting_result} =
           awaiting_turn.decision

  assert {:ok, approved_turn} =
           Spectre.turn(
             ProjectAgent,
             "yes",
             state: awaiting_result.state,
             test_pid: self()
           )

  assert {:needs, %Effect{status: :approved}, approved_result} =
           approved_turn.decision

  refute_received {:project_created, _args}

  assert {:ok, execution} = execute(approved_result)
  assert_receive {:project_created, %{source: "chat"}}
end
```

This test proves three separate facts:

```text
Action proposal != approval != execution
```

If a refactor starts the Action automatically while resolving the Policy,
`refute_received/1` catches it even when the final output looks correct.

A trusted host can resolve the same Policy through one of its declared labels:

```elixir
{:ok, approved_turn} =
  Spectre.Turn.resolve_policy(
    awaiting_turn,
    {:accept, :accepted_terms}
  )
```

An unknown label deserves its own test. The call must return an error and the
Session state must remain unchanged. It is not enough to check that the Action
did not start: a failed approval attempt must not consume or corrupt the
Awaitable either.

## The negative path is first-class behavior

Rejection is not an exception wrapped around the happy path. It is a terminal
lifecycle transition:

```elixir
test "rejection cancels the Effect without invoking the Action" do
  assert {:ok, awaiting_turn} =
           Spectre.turn(
             ProjectAgent,
             "start project",
             test_pid: self()
           )

  assert {:awaiting, _awaitable, awaiting_result} =
           awaiting_turn.decision

  assert {:ok, rejected_turn} =
           Spectre.turn(
             ProjectAgent,
             "no",
             state: awaiting_result.state,
             test_pid: self()
           )

  assert {:completed, %Effect{status: :cancelled} = cancelled, result} =
           rejected_turn.decision

  assert Effect.outcome(cancelled) ==
           {:cancelled, {:policy_rejected, :rejected_terms}}

  assert result.state.pending_effects == []
  refute_received {:project_created, _args}
end
```

A complete Policy matrix should include at least:

- acceptance;
- rejection;
- an unknown reply;
- exhausted attempts;
- expiry;
- an unknown host label;
- a second resolution of the same Awaitable; and
- multiple candidate Awaitables without enough source information to
  disambiguate them.

The `maybe` case is especially useful. It must increment the attempt count and
remain inside the Policy without invoking a classifier or LLM. A short answer
to an open confirmation must not re-enter the normal reasoning loop.

## A fake LLM is an instrument, not the test judge

When a route requires a model, use a deterministic adapter in the normal test
suite. A test double can record every invocation and return a controlled label:

```elixir
defmodule MyApp.TestLLM do
  @behaviour Spectre.LLM

  @impl Spectre.LLM
  def complete(prompt, opts) do
    send(Keyword.fetch!(opts, :test_pid), {:llm_called, prompt})
    {:ok, "PROJECT_SUPPORT"}
  end
end
```

You can now distinguish two invariants:

```elixir
assert_receive {:llm_called, prompt}
assert prompt =~ "PROJECT_SUPPORT"
```

or:

```elixir
refute_received {:llm_called, _prompt}
```

The second assertion is often more important. If a regex or local classifier
already owns sufficient evidence, reaching the correct route after an LLM call
is still a cost, latency, and privacy regression.

Do not use a second model to decide whether a contract test passed. A model can
help with a semantic eval; it must not judge whether a forbidden callback was
invoked.

## The routing corpus also measures model use

For an Agent that combines regex routes, a local classifier, and an LLM
fallback, Spectre includes `mix spectre.eval` to run a JSONL corpus through the
real input and routing pipelines:

```json
{"id":"start-project-exact","input":"start project","expected_route":"START_PROJECT","expected_strategy":"regex","llm":"forbidden","tags":["deterministic"]}
{"id":"project-support-local","input":"I need help with my project","expected_route":"PROJECT_SUPPORT","llm":"forbidden","tags":["local"]}
{"id":"ambiguous-project-request","input":"something is wrong with the setup","allowed_routes":["PROJECT_SUPPORT","ACCOUNT_SUPPORT"],"llm":"required","tags":["ambiguous"]}
```

Use it as a reproducible gate:

```bash
mix spectre.eval MyApp.SupportAgent test/fixtures/routing.jsonl \
  --json tmp/spectre-routing.json
```

The report measures pass rate, route accuracy, strategy usage, LLM policy
violations, and p50/p95 latency. The command exits unsuccessfully when its
declared thresholds are not met.

The interesting property is `llm`: `forbidden`, `allowed`, or `required`. A
route can be correct and the case can still fail because the model was called
when it was not needed.

To inspect one case without executing handlers, Actions, or persistence:

```elixir
{:ok, receipt} =
  Spectre.Router.evaluate(
    MyApp.ProjectAgent,
    "start project",
    state: %Spectre.State{current_flow: :projects}
  )

assert receipt.label == :START_PROJECT
assert receipt.strategy == :regex
refute receipt.llm_called?
```

The receipt contains sanitized operational metadata rather than raw provider
prompts, inputs, or outputs. Routing evaluation does not run the selected
handler, load memory, persist state, or execute Actions: it measures the router
instead of pretending to be an end-to-end test.

## Killing a process is not the same as returning `{:error, reason}`

Spectre runs on OTP. Merely checking the value returned by an adapter does not
prove what happens when a process exits, is killed, or times out at a boundary.

A serious lifecycle test starts the real supervised processes and injects
failure at different points:

```text
input
  -> state load
  -> memory recall
  -> handler and routing
  -> arbitration journal
  -> rendering
  -> state compare-and-set
  -> persistence journal
  -> memory persist
```

At each interruption it should prove that:

- no later callback runs;
- durable revision changes only after the commit;
- no registered zombie process remains;
- the Supervisor recreates only children that should be recreated;
- the next Turn recovers from authoritative state; and
- a late result with stale fencing is rejected.

This is why testing a child specification is not enough. It proves that a
Supervisor *could* start the process, not that pending Effects and Awaitables
survive a real crash.

Spectre's `0.3.0` suite uses real supervised processes precisely to distinguish
normal shutdown, abnormal crash, recoverable state, and orphaned ETS resources.

## A timeout does not prove that the Action failed

Consider this order:

```text
external Action creates the project
  -> the application database commits
  -> the worker crashes before the Spectre receipt
```

From the runtime's perspective, the outcome is ambiguous. Repeating the Action
with a new identity could create two projects.

This is why `Spectre.execute` injects `:effect_id` and `:idempotency_key` into
`ctx.opts`. The application must use that key at the same durable boundary as
the side effect:

```elixir
def create_project(args, ctx) do
  idempotency_key = Keyword.fetch!(ctx.opts, :idempotency_key)
  MyApp.Projects.create_once(idempotency_key, args)
end
```

`create_once/2` must be a genuinely idempotent application operation, for
example protected by a unique constraint persisted with the project. A
temporary ETS table or process flag is not enough after restart.

The corresponding contract test should crash **after** the business commit,
restart the Session, and observe:

- multiple external attempts;
- the same idempotency key on every attempt;
- one project or payment in the domain system; and
- one terminal outcome accepted by the Run.

OTP can restart the worker. It cannot reverse a bank transfer or delete the
second order created by mistake.

## Morph adds regression tests before activation

ExUnit verifies the program and application boundaries. Morph must also verify
that a new Definition does not break behavior that is already protected.

A minimal corpus can declare behavior that must remain unchanged:

```elixir
protected_cases = [
  %{
    "id" => "weather-stays-unhandled",
    "input" => "weather",
    "expected_outcome" => "clarify",
    "context" => %{"scope" => "support"},
    "llm" => "forbidden"
  }
]

change =
  instance
  |> Spectre.Morph.change(
    by: "operator:author",
    reason: "Teach the Agent about refunds"
  )
  |> Spectre.Morph.mount_skill("refunds",
    match: {:exact, "refund"},
    reply: "Refund policy applies to: {{input.text}}",
    scopes: [:support],
    token_cap: 128
  )
  |> Spectre.Morph.evaluate(cases: protected_cases)
```

Morph compares the parent and Candidate over the same corpus and derives more
obligations from the real Definition diff. A Candidate-owned case proving the
new Skill must pass, but it does not increase the protected score: a change
cannot write easy tests for itself and use them to hide a regression.

The full proof does not end with `evaluate/2`. Run a real `Spectre.turn/3`
before and after activation and verify that:

- the new route does not exist beforehand;
- an unapproved Candidate cannot change live behavior;
- a new Run uses the new Definition after activation;
- an already open Run remains pinned to the previous Definition; and
- a stale Candidate requires an explicit rebase.

Evolution without regression tests is not learning. It is drift.

## Real providers belong in a separate suite

The normal suite should be fast, offline, and deterministic. That means fake
LLMs, embedding fixtures, controlled clocks, and instrumented adapters.

But a fixture does not prove that a real model loads, a NIF works, or a provider
still honors its contract. A small number of opt-in tests with real
integrations are also necessary.

The separation matters:

- deterministic tests run continuously;
- live-provider evals can cost money and vary;
- native or network tests can have a dedicated job;
- a frozen fixture is not presented as proof of real inference; and
- a provider failure does not make every runtime contract test red.

Spectre's own suite applies this distinction to semantic cache: the offline
contract checks call cardinality and persisted vectors; the real ExFastembed
test runs separately and explicitly.

## The minimum matrix for a production Agent

Before allowing an Agent to own a real side effect, I would require at least
these cases:

| Case | Required proof |
| --- | --- |
| Deterministic route | Correct route and zero LLM calls |
| Ambiguous route | Model invoked only when allowed or required |
| Protected Action | No invocation before the Policy |
| Rejected Policy | Cancelled Effect, cleared pending state, zero invocations |
| Invalid host resolution | Error and unchanged state |
| Action retry | Same idempotency key and one business effect |
| Store failure before commit | Definite failure and unchanged durable revision |
| Store failure after commit | Ambiguous outcome, recovery, and no blind retry |
| Session crash | Pending state restored without zombies |
| Morph Candidate | Protected corpus unchanged before activation |
| Real provider | Small opt-in suite distinct from offline contracts |

You do not need to write everything on the first day. You do need to know
which claim each test actually proves.

## What Spectre cannot prove for your application

The framework suite can prove the framework lifecycle. It cannot automatically
prove that your domain boundary is correct.

The host application must add end-to-end tests for:

- authorization against current business data;
- durable idempotency in its own Actions;
- State Store adapters and their real commit semantics;
- deduplication of message and notification delivery;
- secret and sensitive-data handling;
- product-specific prompts, models, and corpora;
- application rollback where the external world permits it; and
- operational recovery when the outcome remains ambiguous.

A Policy confirms an intention. It does not replace authorization at the
capability boundary. An idempotency key supplied by Spectre deduplicates
nothing unless the Action persists it. A Supervisor does not make an external
API transactional.

These limits do not weaken the model. They make the owner of each proof
visible.

## A practical pipeline

For most projects I would begin with this pipeline:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix test --cover
mix spectre.eval MyApp.SupportAgent test/fixtures/routing.jsonl \
  --json tmp/spectre-routing.json
```

I would keep opt-in jobs for live providers, models, embeddings, and external
services separate.

Spectre 0.3.0 includes a [complete guide to testing
contracts](https://github.com/elchemista/spectre/blob/0.3.0/docs/TESTING.md),
and its [end-to-end Turn
suite](https://github.com/elchemista/spectre/blob/0.3.0/test/full_agent_turn_test.exs)
exercises the same boundaries with instrumented adapters. The [supervised
lifecycle suite](https://github.com/elchemista/spectre/blob/0.3.0/test/system_lifecycle_contract_test.exs)
covers crashes, restore, and idempotency after a business commit.

## The model can be wrong without owning the system

A useful agent does not become deterministic because we want it to. The model
will continue to misunderstand some inputs, change behavior between versions,
and produce answers no corpus anticipated.

The runtime's job is not to pretend that uncertainty can be eliminated. Its
job is to surround it with components about which we can make precise claims:

- this route must not call the model;
- this Effect cannot execute now;
- this rejection is terminal;
- this commit is ambiguous and must not be blindly repeated;
- this Candidate cannot be activated; and
- this late result no longer belongs to the current revision.

That is the difference between testing a conversation and testing a system.

Spectre does not ask us to trust the model's intelligence less. It asks us
never to confuse intelligence with authority. **The model can remain
probabilistic; the boundaries within which it operates must be falsifiable.**
