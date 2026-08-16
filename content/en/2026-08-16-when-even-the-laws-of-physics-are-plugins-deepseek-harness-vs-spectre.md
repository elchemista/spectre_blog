---
title: "When Even the Laws of Physics Are Plugins: DeepSeek Harness vs Spectre"
slug: "deepseek-harness-vs-spectre-plugins-or-kernel"
lang: "en"
status: published
date: 2026-08-16
updated: 2026-08-16
category: "Software Development"
tags: ["AI agents","agent architecture","DeepSeek Harness","Spectre","Elixir","OTP","plugin systems","enterprise AI"]
seo_title: "DeepSeek Harness vs Spectre: Plugins or Kernel?"
seo_description: "DeepSeek Harness makes components replaceable through plugins. Spectre keeps a governed kernel. A comparison of composition, authority, state, and recovery."
cover_alt: "Two Agent architectures compared, one composed entirely from plugins and one built around a governed kernel"
---

"Everything is a plugin" is an irresistible sentence for a developer.

It promises freedom. Change the model, change the tool registry, change the
database, change the loop. If you dislike a choice, replace it through
configuration and keep working.

Then the Agent receives production access and the question changes:

> If everything is replaceable, which part guarantees that some things remain true?

That is why the new
[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) interests
me so much, while its architectural thesis does not fully convince me. Not
because plugins are wrong. DeepSeek uses them much more seriously than the
slogan might suggest. The point is that an operational runtime needs to
distinguish what may vary from the laws defining correctness, ownership, and
authority.

On this distinction, [Spectre 0.3.2](https://github.com/elchemista/spectre/tree/0.3.2)
takes an almost opposite path.

DeepSeek Harness wants to make the system replaceable.

Spectre wants to make the Agent governable.

Both are valid ideas. They are not the same idea, however, and for an
enterprise product I strongly prefer the second.

## A snapshot, not a final verdict

DeepSeek Harness has only just become public. At the time of writing, its
[root package](https://github.com/deepseek-ai/deepseek-harness/blob/47f943859bef60e4160492346772ded9b24f765a/package.json)
declares `0.1.0-rc.5`, while the
[README](https://github.com/deepseek-ai/deepseek-harness/blob/47f943859bef60e4160492346772ded9b24f765a/README.md)
calls it a developer preview and warns that compatibility-breaking changes
will arrive.

This article is therefore not trying to declare an eternal winner. It compares
two architectural decisions visible today.

The products are different too. DeepSeek Harness is a coding harness with Web
and headless profiles, designed to be recomposed by its user. Spectre is an
embeddable Elixir runtime where Agents, Works, Vigils, Policies, and Effects
must live beyond a single interaction.

The interesting comparison is not the number of features. It is the question:

> Where should the constitution of an agentic system live?

## What "everything is a plugin" really means

It is not just marketing. The
[architecture documentation](https://github.com/deepseek-ai/deepseek-harness/blob/47f943859bef60e4160492346772ded9b24f765a/docs/architecture.md)
states that the model, tool registry, session log, and agent loop are
configuration-replaceable plugins. It also says there is no privileged core
to patch.

A DSH configuration begins as a layered plugin tree:

~~~text
base bundle
      +
profile bundles
      +
profile patch
      +
home patch
      +
CLI overlay
      |
      v
running Cordis tree
~~~

Each layer can replace the complete configuration of a row or insert a new
one. A patch watcher can recompose the tree while the system is running.
Plugin registrations are reversible Effects, so unload and teardown can remove
them predictably.

This is genuinely powerful. It is not the usual callback array called a
"plugin system" to make a README look more sophisticated.

## Cordis is the part that must be taken seriously

DSH is built on [Cordis](https://github.com/cordiverse/cordis), a meta-framework
for what its authors call spatiotemporal composability. The
[paper](https://github.com/cordiverse/paper) separates two problems:

- temporal composability, meaning a component can be removed and its effects
  on the context reversed;
- spatial composability, meaning dependencies can be declared and components
  can react when available services change.

In practice, a plugin declares dependencies with `inject`, finds services
through typed keys in `ctx`, registers reversible Effects, and communicates
through typed events. Events may use `emit`, `parallel`, `serial`, or
`waterfall` dispatch.

The
[Cordis primer](https://github.com/deepseek-ai/deepseek-harness/blob/47f943859bef60e4160492346772ded9b24f765a/docs/cordis-primer.md)
explains waterfall semantics clearly. A listener receives the request and
`next()`. It may modify the request and delegate to the next listener, or avoid
calling `next()` and close the chain with its own decision.

This is not accidental extensibility. It has declared dependency injection,
typed services, teardown, scoping, and dispatch contracts. DSH uses Cordis with
considerable discipline.

That is exactly why the disagreement is interesting. I am not criticizing a
naive implementation. I am discussing the limit of a well-implemented idea.

## DeepSeek has already met the problems of serious Agents

As soon as an Agent can use real tools, composability alone is not enough. The
DSH documentation shows that the project knows this.

Its
[tool pipeline](https://github.com/deepseek-ai/deepseek-harness/blob/47f943859bef60e4160492346772ded9b24f765a/docs/tool-execution-pipeline.md)
does not simply execute what the model requests. The path includes:

~~~text
persisted tool/call
      |
tools/pre-execute waterfall
      |
approval, when required
      |
monotonic guards
      |
tools/execute waterfall
      |
tool body
      |
tools/post-execute waterfall
      |
finalizeContent
      |
immutable tools/result
      |
persisted tool/result
~~~

Monotonic guards can deny or abstain, but a deny is not transformed into allow
by a later listener. If approval is unavailable, the path fails closed. The
final observed outcome is frozen and authoritative for that pipeline.

The
[Session](https://github.com/deepseek-ai/deepseek-harness/blob/47f943859bef60e4160492346772ded9b24f765a/docs/subsystems/session.md)
is also designed seriously. It is an append-only log of typed events and model
history is derived from the log rather than maintained as a second copy.
Model-visible input, chunks, messages, tool calls, and their results are
reconstructable. Persistence adds revisions, validation, torn-tail repair, and
explicit closure for interrupted Turns.

So no, DeepSeek Harness is not a fragile loop with a marketplace attached. It
has contracts, recovery, and mitigations that many frameworks lack.

But those mitigations also reveal the paradox.

To build a system where everything is a plugin, DSH had to reintroduce
monotonic guards, immutable outcomes, service ownership, durable logs, and
decision points that behave almost like a kernel.

## The problem is not plugins, it is emergent behavior

One waterfall is understandable. Ten isolated plugins are understandable. The
behavior of the complete composition can be much harder to understand.

In DSH, effective behavior derives from something like this:

~~~text
behavior =
    plugin tree
  + layer order
  + rows replaced by patches
  + active Context dependencies
  + listeners and their order
  + waterfall short circuits
  + selected providers
  + runtime state
~~~

Order is not always a weakness. `inject` removes a great deal of manual
sequencing and monotonic guards protect local decisions. The problem is the
global reasoning load.

To understand why a tool executed, reading the tool is not enough. We need to
know which profile booted, which bundles compose it, which patches replaced
rows, which listeners were active, who called `next()`, who closed the
waterfall, and which provider owned the service at that moment.

For a coding harness controlled by its user, this may be a reasonable price.
It may even be the feature.

For a runtime embedded in an enterprise product, the same freedom becomes a
verification cost.

## A default core is not yet a constitution

The DSH documentation still uses the phrase "core packages" for Session,
system prompt, tools, Agent, and agent loop. This is not a contradiction. They
are the spine of the composition shipped by DeepSeek.

But the architecture document specifies that these components are also
plugins and that any row shown by `--dump-config` can be replaced by a patch.

So "core" identifies what the distribution normally mounts. It does not
necessarily identify a constitution that every conforming composition must
preserve.

The monotonic guard is a good example. Within the standard pipeline, a deny is
monotonic. The broader system promise remains the replaceability of the
pipeline, registry, and loop that use it.

I am not claiming that a patch can secretly bypass every control. I am saying
that the security property depends on the composition that actually booted.
That is a legitimate choice, but it requires a deployment to prove that its
plugin tree preserves the expected invariants.

Spectre asks the question differently: which invariants must not depend on
that composition?

## Spectre places some laws in the kernel

The [Spectre architecture](https://github.com/elchemista/spectre/blob/0.3.2/docs/ARCHITECTURE.md)
separates conversational decisions from application authority. A model may
classify, reason, and propose work. Only deterministic Lifecycle and Policy can
make that work executable.

The constitutional path looks like this:

~~~text
Definition
    |
    v
Instance, owner of AgentRef + Subject
    |
    v
Run / Lifecycle / Policy
    |
    v
Effect or Invocation
    |
    v
host application authority
~~~

Model, memory, perception, planning, channel, transport, and mission planner
may all change around this chain. They cannot become alternative owners of
canonical state.

A Definition is immutable and content-addressed. The Instance is the sole
local owner of state for one `AgentRef + Subject` pair. Runs preserve identity
and continuation. Temporary Runners perform slow operations, but they own no
canonical state and do not decide semantic retry.

When a result returns, the Instance checks loop id, attempt id, epoch, fencing
token, context revision, control generation, and trigger generation before
applying it. A result valid for a world that no longer exists is discarded.

These are not optional features. They are the laws of physics of that runtime.

## Canonical state: a Session log and an Instance are not the same thing

DSH makes a very good choice: the append-only Session is the source of truth
for the interaction and history is derived from it. For a coding harness, this
is a strong foundation. Resume, fork, UI, and persistence can read the same
event vocabulary.

Spectre addresses a different domain. An Instance can own several Runs and
typed sections for Flow, Work, Vigil, controllers, inference, control, and the
Receipt outbox. Every accepted change advances precise revisions. An ambiguous
checkpoint fences further automatic writes until reconciliation proves the
durable state.

Its operational path therefore looks like this:

~~~text
Instance creates a fenced snapshot and Attempt
      |
temporary Runner performs one operation
      |
Progress or Result returns to the Instance
      |
validate -> reduce -> commit
~~~

I would not call the DSH Session weak. I would say it answers the question
"what is the canonical history of this interaction?".

The Spectre Instance also answers another question: "who may still change the
operational state of this Agent after concurrency, restart, revocation, and
update?".

For long-running Agents, that question becomes decisive.

## Cognition is not authority

This is Spectre's most important separation:

~~~text
model proposes an Action
      |
Effect is staged
      |
deterministic Policy requests or denies authority
      |
approval is committed
      |
host rechecks authorization and credentials
      |
Effect is executed
      |
terminal outcome is committed
~~~

Approval and execution are separate commits. A valid schema proves argument
shape, not authority. An idempotency key lets the application deduplicate, but
does not pretend an external provider is exactly once. If a write may have
happened, the outcome may remain ambiguous instead of authorizing a creative
retry.

DeepSeek Harness has a robust permission and approval pipeline. The difference
is not "DSH executes blindly while Spectre does not." That would be false.

The difference is ontological. In Spectre, authority explicitly belongs to
Definition, Lifecycle, Policy, and the host. The model and extensions can
contribute cognition without rising above that chain.

## Spectre Stack is a tighter compromise

Spectre does not reject composition. Its
[Stack](https://github.com/elchemista/spectre/blob/0.3.2/docs/STACK.md)
installs packages, verifies dependencies, conflicts, and ownership, and
produces closed references with immutable digests.

You can integrate Prism, Kinetic, Mnemonic, Lens, Directive, Beam, Pulse,
Ledger, Lab, and host adapters. Core does not need to know their clients,
processes, or credentials. Some packages may consume contracts from other
packages, but they do not become a second canonical runtime.

The decisive rule is:

> installed does not mean authorized.

Installing a capability declares that it exists in the environment. It does
not automatically make it visible to the planner, available to every Flow, or
executable without Policy. Binding, protection, and authorization remain
separate decisions.

For me, this is the right compromise:

> Everything that may vary has an explicit extension boundary. Everything that
> defines correctness stays in the kernel.

Not "everything is a plugin," but not "nothing is replaceable" either.

## A concrete failure reveals the difference

Imagine an Agent that can approve a refund. The provider accepts the
operation, then the connection drops before the response arrives.

In both systems we can build logging, approval, and persistence. The
architectural question is where the rule preventing an unproven second
execution lives.

In a universally composable harness, that property emerges from the active
registry, the tool pipeline, registered guards, persistence, and booted
configuration. The composition must preserve the entire chain.

In Spectre, the Effect Lifecycle, separation between approval and execution,
ambiguous outcome, and Run fencing belong to the runtime. The host must still
implement real idempotency and reconciliation at the payment provider, but an
adapter cannot simply mutate canonical state and declare the problem solved.

Spectre does not remove application responsibility. It gives that
responsibility a precise place to exist.

## Architectural comparison

| Topic | DeepSeek Harness | Spectre 0.3.2 |
| --- | --- | --- |
| Primary goal | Reconfigurable coding harness | Governed runtime embedded in a product |
| Composition unit | Cordis tree of plugins, bundles, and patches | Definition and Stack above a deterministic kernel |
| Agent loop | Replaceable plugin | Constitutional Run and Runtime with extension boundaries |
| Primary state | Append-only Session event log | Canonical Instance per AgentRef + Subject, with several domains and Runs |
| Extension | Services, events, waterfalls, and reversible Effects | Callbacks, providers, Stack Refs, and package manifests |
| Ordering | Layers and listeners participate in behavior | Ordering is limited to declared boundaries, Lifecycle remains central |
| Tool safety | Pre, approval, monotonic guards, execute, post, final outcome | Action catalog, schema, Policy, Effect Lifecycle, host authority |
| Recovery | Session persistence and repair | Revisions, CAS, ambiguity fence, Attempt and epoch fencing |
| Hot replacement | A central Cordis goal | Deliberately limited by Definitions, generations, and digests |
| Installation | A row can alter the composition | Installation does not grant authority |
| Main strength | Maximum harness adaptability | Runtime legibility under concurrency and failure |

The table does not say one column is universally better. It says the two
architectures optimize different costs.

## Where DeepSeek Harness is probably better

If I want to build a laboratory for coding Agents, DSH is extremely attractive.

I can replace the loop, change the Session implementation, mount a remote
filesystem provider, change the sandbox, add a UI, create a headless profile,
and experiment with middleware intercepting every phase. Cordis makes reload
and teardown part of the model rather than leaving them to scattered
conventions.

For research, hacker tools, customizable shells, and platforms whose users
must be able to recompose almost everything, DeepSeek Harness may be better
than Spectre.

I would not copy that priority into Spectre, however. Making the Run reducer or
Instance ownership replaceable would not add useful freedom for its goal. It
would make correctness an emergent property of configuration.

## Composable harness and governed runtime

The positioning distinction can be simple:

~~~text
DeepSeek Harness
Composable agent harness

Spectre
Governed agent runtime
~~~

DeepSeek Harness says: replace everything.

Spectre should say: extend everything that may change, protect what must remain
true.

The first message is ideal when the person using the system is also the person
recomposing its architecture. The second is more interesting when the Agent
enters a bank, SaaS, ERP, industrial system, financial workflow, or customer
operations center.

In those contexts, knowing that an approval plugin exists is not enough. We
must know who owns authority when that plugin, provider, Runner, database, or
network fails.

## The most interesting part of the new Harness

DeepSeek has unintentionally strengthened one of Spectre's central theses.

To build serious Agents, even a project founded on total replaceability had to
introduce immutable outcomes, durable logs, monotonic guards, recovery, typed
events, ownership, and explicit approval.

This is not a defeat for DSH. It is evidence that the real problem is not
connecting a model to a tool. The problem is preserving verifiable properties
while probabilistic components and external systems fail.

DeepSeek tries to obtain those properties inside a universally modifiable
composition.

Spectre says that some of those properties are the kernel.

For a coding harness, I gladly choose the freedom to dismantle the machine.

For an operational Agent, I choose a system where I can change muscles,
senses, and memory without accidentally replacing the laws of physics.

That is why "everything is a plugin" does not convince me as the constitution
of an enterprise runtime. Not because it offers too much extensibility, but
because it treats replaceability as more valuable than the permanence of some
invariants.

The final question is not how many plugins I can install.

It is much simpler:

> Who owns authority when everything else can fail?

In Spectre, the answer is deliberately difficult to replace.
