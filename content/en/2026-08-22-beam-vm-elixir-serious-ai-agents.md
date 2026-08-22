---
title: "BEAM Wasn't Built for AI, but It Feels Made for Serious Agents"
slug: "beam-vm-elixir-serious-ai-agents"
lang: "en"
status: published
date: 2026-08-22
updated: 2026-08-22
category: "Software Development"
tags: ["BEAM VM","Elixir","Erlang","OTP","AI agents","fault tolerance","concurrency","Spectre"]
seo_title: "Why BEAM and Elixir Fit Serious AI Agents"
seo_description: "BEAM was not built for AI, but isolated processes, supervision, message passing, and OTP make it an unusually strong foundation for serious Agent systems."
cover_alt: "An AI Agent running as a set of supervised Elixir processes on the BEAM VM"
---

When people talk about artificial intelligence, the technology choice seems
almost automatic.

Python for the model. CUDA for the GPU. An inference server, a few APIs, and a
framework that connects prompts to tools.

That makes perfect sense when the problem is training or serving a model. A
serious Agent, however, is not the model it uses. The model is only one of its
components and often not even the component that stays active the longest.

An Agent exists before a model call and must continue to exist afterward. It
receives messages, owns state, waits for the network, starts jobs, handles
timeouts, coordinates tools, requests approvals, produces effects, and must
know what to do when any of those operations fail.

The difficult part begins exactly where the prompt demo ends.

This is where a virtual machine created decades before the current AI wave
starts to look surprisingly modern.

BEAM was not designed for Large Language Models. Erlang was born at Ericsson,
and [Erlang/OTP was built and battle-tested for robust, fault-tolerant,
distributed applications](https://www.erlang.org/about), in a world where one
part of a system had to fail without interrupting the entire service.

It was not artificial intelligence. It was telecommunications.

But the problem already had a familiar shape: huge numbers of concurrent
activities, state that lives over time, asynchronous communication, unreliable
networks, partial failures, and the need to recover without shutting down the
whole system.

It is difficult to imagine a description closer to a modern Agent runtime.

## An Agent is not a function

Many Agent examples begin with a function that receives a string, calls a
model, and returns an answer.

That is an excellent way to explain the first example. It becomes a dangerous
mental model when the system grows.

Imagine an Agent analyzing documents for a customer. While it works, a new
instruction arrives, a model call begins streaming tokens, an external tool
times out, and a policy requests human approval. Another scheduled job must
start in ten minutes, while the current one must remain pausable and
cancellable.

This is no longer a function. It is a small concurrent system.

~~~text
Agent Instance
  ├── conversation and state
  ├── active Run
  ├── background Work or Vigil
  ├── model Invocation
  ├── Effect waiting for policy
  └── timers, messages, and notifications
~~~

This does not mean that every line must always map to a separate process. It
means they have different owners, lifecycles, and failure domains.

BEAM gives us a natural way to represent them without turning everything into
nested callbacks, shared threads, or a collection of database records that
some worker must continuously reinterpret.

## BEAM processes are ownership boundaries

An Erlang process is not an operating system process. It is a much lighter
entity managed directly by the VM. The official documentation describes
[Erlang processes as lightweight and suitable for systems with very large
numbers of concurrent processes](https://www.erlang.org/doc/system/eff_guide_processes.html).

Each process owns its state and mailbox. At the programming model level, it
communicates with other processes through messages rather than directly
mutating their memory.

This changes how we can build an Agent.

One Instance can own the canonical state for a particular Agent and Subject.
Requests arrive as messages. Temporary work can run under another process. The
owner receives the result and decides whether it is still valid before
applying it.

We get more than concurrency. We get a clear boundary around the most
important question in a stateful system:

> Who owns this state, and who is allowed to change it?

In Elixir, [`GenServer`](https://hexdocs.pm/elixir/GenServer.html) provides a
standard way to build these owners. It can maintain state, receive synchronous
calls and asynchronous messages, handle timeouts, participate in a supervision
tree, and be observed using shared tooling.

Of course, not every function belongs inside a GenServer. The Elixir
documentation itself warns that a process should model a runtime property,
such as mutable state, concurrency, or failure, rather than being used merely
to organize code.

A long-running Agent has exactly those runtime properties. We are not
inventing processes because we like OTP. We are giving an explicit shape to
something that already exists in the system.

## Supervision changes how we think about failure

An LLM provider can time out. A parser can receive an incomplete response. An
integration can return invalid data. A process handling a stream can terminate
while the user is sending a new instruction.

In many runtimes, handling these cases becomes scattered across `try` blocks,
retries, callbacks, and message queues. With OTP, failure is a declared part of
the architecture.

A [Supervisor](https://hexdocs.pm/elixir/Supervisor.html) knows which processes
it must start, stop, and restart. A supervision tree describes which components
depend on one another and which part must be rebuilt when something terminates
abnormally. A
[`DynamicSupervisor`](https://hexdocs.pm/elixir/DynamicSupervisor.html) can
manage children created on demand, while a
[`Task.Supervisor`](https://hexdocs.pm/elixir/Task.Supervisor.html) isolates
temporary jobs without leaving them outside the application's lifecycle.

This does not mean that "let it crash" means ignoring errors. It means
separating the code that performs work from the code that decides how the
system should recover. A component can fail clearly. Its supervisor contains
the damage and applies a known strategy.

For Agents, this separation is precious. A broken model call should not bring
down every conversation. A failed Work should not corrupt the Instance that
started it. An unstable external adapter should not become the implicit owner
of the Agent's lifecycle.

But precision matters here too: restart does not mean recovery.

A Supervisor can start a process again, but it cannot invent state we did not
save. Durability, checkpoints, idempotency, and reconciliation remain
responsibilities of the application architecture.

BEAM provides the mechanism that contains the failure. A serious runtime must
also know which durable truth to recover from.

## Scheduling and garbage collection shaped for concurrency

Agents spend an enormous amount of time waiting.

They wait for the model provider, a database, an API, human approval, a user
message, or the next interval of a periodic task. The problem is not only
executing one function quickly. It is keeping many activities alive without
allowing one of them to block all the others.

BEAM distributes runnable processes across multiple schedulers and uses a
reduction budget to force a context switch after a bounded amount of work. The
VM is designed so that many processes can make progress without depending on
one application-level event loop.

Memory follows the same philosophy. Erlang uses a
[per-process generational garbage collector](https://www.erlang.org/doc/apps/erts/garbagecollection.html).
A collection normally concerns the process that owns that heap instead of
imposing a global pause on every activity in the application each time.

For a runtime hosting many independent conversations and jobs, this is a
structural advantage. An Instance creating large amounts of temporary data
does not necessarily drag every other Instance into its garbage collection.

This does not mean BEAM makes every workload automatically fast. It means the
VM is optimized to keep a system made of many concurrent activities
responsive, which describes an Agent system far better than a single numerical
benchmark does.

## Message passing as a control interface

Erlang processes communicate through
[asynchronous signals and messages](https://www.erlang.org/doc/system/ref_man_processes.html).
Each process receives messages in its mailbox and decides how to interpret
them.

For an Agent, this is more than an internal implementation detail. It can
become the natural language of operational control.

A user can send new information while a Work is running. The runtime can ask
the job to pause, update its context, and resume. A process can monitor a
worker and receive a signal when it terminates. A timer can produce the next
step of a Vigil. A unique reference can distinguish a valid result from a late
response belonging to an attempt that has already been replaced.

BEAM already provides mailboxes, monitors, links, timers, and process
identities. It does not solve the protocol automatically, but it lets us build
that protocol from primitives sharing the same runtime semantics.

This distinction matters. A late model response must not be applied merely
because it finally arrived. It must still belong to the correct Run, the
correct attempt, and the correct revision.

The VM gives us transport and isolation. The Agent runtime adds fencing,
revisions, and commit rules.

## Elixir makes this machine usable

BEAM is the foundation, but Elixir makes building complex systems on top of it
pleasant.

Pattern matching, immutable data, protocols, and pipelines let us describe
transitions without constantly hiding state inside mutable objects. Macros
make it possible to create readable DSLs that become verifiable structures at
compile time, rather than leaving behavior only inside strings and informal
configuration.

This is especially useful for an Agent. Flows, policies, actions, and skills
can read like a map of behavior while compiling into a precise form the
runtime can inspect.

Elixir also brings a mature ecosystem for HTTP, databases, telemetry,
streaming, and realtime interfaces. Phoenix and LiveView can display an
Agent's state while the processes owning that state continue living outside
the page rendering cycle.

It is not true that Elixir must remain entirely outside numerical work either.
[Nx](https://hexdocs.pm/nx/Nx.html) provides tensors and numerical computing,
while [`Nx.Serving`](https://hexdocs.pm/nx/Nx.Serving.html) organizes inference
and batching. EXLA, Axon, and Bumblebee can bring classifiers, embeddings, and
some models directly into the BEAM ecosystem.

The point, however, is not to prove that every model should run in Elixir.

The point is that Elixir can be the control plane coordinating local models,
GPUs, Python services, and remote providers without surrendering ownership of
the Agent to any of them.

## Where BEAM is not magic

Python and the CUDA ecosystem remain the dominant choice for training large
models and developing new numerical architectures. Heavy computation does not
suddenly become cheap because an Elixir process started it.

Long CPU-bound work, poorly written NIFs, and blocking native calls can damage
the VM's responsiveness. These workloads must move to dirty schedulers, ports,
carefully designed native libraries, or separate services. A mailbox can also
grow without bound when its protocol lacks backpressure and limits.

Distribution between BEAM nodes is powerful, but it does not replace a
strategy for network partitions, security, consistency, and deployment. As we
have already seen, a supervision tree does not replace a database or a durable
checkpoint either.

These are not arguments against BEAM. They are why distinguishing the VM from
the architecture built on top of it matters.

BEAM offers extraordinarily suitable primitives. It does not make decisions
about ownership, authority, persistence, and recovery for us.

## Why I chose Elixir for Spectre

This is exactly why I chose Elixir to build
[Spectre 0.3.2](https://github.com/elchemista/spectre/tree/0.3.2).

I did not choose it because Elixir was the most popular language in AI, nor
because I wanted to rewrite in Elixir what Python already does well.

I chose it because a model is probabilistic, while the system granting that
model state and authority cannot be merely probabilistic.

In Spectre, an Instance owns canonical state. Runs, Works, Vigils, and
Invocations have explicit lifecycles. An Effect describes an action, but the
model does not execute it. A Policy deterministically decides which gates are
required, and the host retains final authority.

These ideas were not added despite OTP. They became natural because OTP keeps
pushing us to ask who owns a process, who supervises it, how it communicates,
and what happens when it fails.

BEAM provides the physics of the system. Spectre tries to build the
constitutional laws of an Agent on top of it.

## The VM underneath the model matters

BEAM is not an AI framework. That is exactly what makes it so interesting for
AI.

It does not try to be the model, vector database, provider, or tool. It offers
an environment in which all these components can be coordinated without
becoming the uncontrolled center of the system.

The model may change. The provider may fail. A tool may time out. A job may be
cancelled. The Agent must still preserve identity, state, lifecycle, and
authority.

Python answers one question extremely well: how do I train and run this model?

Elixir and BEAM answer a different question:

> How do I keep many intelligent, concurrent, imperfect systems alive, letting
> them fail without losing control of the application?

BEAM was not born for AI Agents.

But the more serious Agents become, the more it feels as if BEAM had been
waiting for them all along.
