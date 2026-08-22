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
seo_description: "BEAM was not built for AI, but isolated processes, supervision, messages, and OTP make it a strong foundation for serious Agent systems."
cover_alt: "An AI Agent running through supervised Elixir processes on the BEAM VM"
---

When I started building Spectre, choosing Elixir for a project connected to
artificial intelligence felt almost provocative.

The usual path through the AI world is already well marked. You begin with
Python, reach for CUDA when a GPU becomes necessary, and add a server to expose
the model. Elixir rarely enters that conversation. When it does, someone will
usually ask why you would make life harder by choosing a language outside the
center of the machine learning ecosystem.

At first, that is a fair question. If I wanted to train a new Large Language
Model, Elixir probably would not be my first tool. But while working on Spectre
I realized that the model was only one part of the problem. It was the most
visible part, not necessarily the hardest one.

A real Agent must continue to exist after a model call ends. It must remember
its state, receive new instructions, wait for external services, stop a job,
resume it, and decide whether a late response is still valid. If it can take
actions, it must also know who is allowed to authorize them and what should
happen when something fails halfway through.

At that point, the question is no longer only which model to use. The question
becomes what kind of system we want to build around the model.

That is where Elixir and BEAM started to feel less like an unusual choice and
more like an obvious one.

## The moment an Agent stops being a function

Imagine an Agent analyzing documents for a customer. It has already started a
search, the model is producing a response, and an external service is taking
longer than expected. Meanwhile, the customer sends another message with an
important detail that changes the meaning of the task.

The Agent should receive that message without waiting for everything else to
finish. It may need to pause the search, update its context, and resume from a
coherent point. If the old response from the external service arrives in the
meantime, the Agent should not apply it blindly just because it finally
arrived.

In a demo, we can represent all of this as a function that accepts a string and
returns an answer. In a real product, that function quickly becomes a group of
activities living at the same time. Some last a few seconds, while others may
remain active for hours. Some wait for the network, while others wait for a
person. Any one of them may fail without the whole Agent having to disappear.

This shape looked much less like a simple AI application and much more like a
concurrent system.

The interesting part is that BEAM was created to face a similar problem long
before we talked about Agents. Erlang was developed at Ericsson for systems
that had to remain available even when one part stopped working. Erlang and
OTP later became a foundation for distributed, fault tolerant applications
where stopping everything was not an acceptable response. The
[official Erlang story](https://www.erlang.org/about) begins with
telecommunications, not artificial intelligence.

Yet telecommunications already had many of the difficulties we now find in
Agent systems. There were many activities happening at once, messages arriving
at different times, state that had to live for a long time, and failures that
could not be allowed to spread everywhere.

The name of the problem changed. Its shape did not change nearly as much.

## A small process can create a very large boundary

The first striking thing about BEAM is the way it treats processes.

An Erlang process is not a heavy operating system process. It is a small unit
managed by the virtual machine, with its own identity, state, and mailbox. The
Erlang documentation explains that these
[processes are lightweight and designed to exist in large numbers](https://www.erlang.org/doc/system/eff_guide_processes.html).

For me, the important part is not only how many thousands of processes can be
started. It is the boundary each process creates.

If one process owns the state of an Agent, other components do not reach into
that state and change it whenever they want. They send a message. The owner
receives the request, checks whether it still makes sense, and decides how to
change.

That makes one question very concrete, even though it remains hidden in many
systems: who actually owns this state?

With [`GenServer`](https://hexdocs.pm/elixir/GenServer.html), Elixir provides a
common way to build this kind of owner. There is no need to turn every function
into a process. A process makes sense when something must live over time,
receive events, protect state, or represent a failure boundary. An Agent that
can be interrupted, updated, and resumed has exactly those properties.

A temporary job can live in another process. If that job fails, the process
that owns the Agent does not need to lose its state. If the job completes, it
sends its result back to the owner, which can still decide whether to accept
it. This separation may sound like a technical detail, but it completely
changes how we reason about the system.

We are no longer hoping every operation finishes in the correct order. We are
giving each part a clear responsibility.

## Failing without taking everything else down

Sooner or later, a model provider times out. A connection closes during a
stream. A parser finds a response it did not expect. These are not exceptional
events. They are the normal environment in which an Agent lives.

OTP brings failure into the design of the application. A
[`Supervisor`](https://hexdocs.pm/elixir/Supervisor.html) knows which processes
are under its care and how to react when one of them terminates. We do not have
to spread the same recovery logic across every function. We can decide in one
place what should restart and which part of the system should remain intact.

The famous idea of letting a process fail is often explained badly. It does
not mean ignoring errors. It means refusing to let a half broken component
continue hiding inconsistent state. The process ends clearly, and the level
supervising it decides how to rebuild it.

Restarting does not magically recover everything, of course. If important
state was never saved, a Supervisor cannot invent it. A serious system still
needs checkpoints, operations that can safely be repeated, and a durable truth
from which it can start again.

BEAM still gives us something valuable before persistence enters the picture.
It lets us contain the failure. One broken model call should not bring down
every conversation. An unstable integration should not become the center on
which the life of the Agent depends.

When many Agents work inside the same system, this property stops being elegant
theory and becomes operational survival.

## The kind of concurrency Agents actually need

An Agent spends much of its life waiting. It waits for the model, a database
query, an API, a new message, or approval from a person. While one Agent waits,
the others must be able to continue working.

BEAM distributes ready processes across its schedulers and measures work using
reductions. After a limited amount of work, one process makes room for others.
We do not have to build a single application loop on which the responsiveness
of the whole system depends.

Memory follows a similar idea. Erlang uses a
[generational garbage collector for each process](https://www.erlang.org/doc/apps/erts/garbagecollection.html).
When a process needs to clean its own space, it does not normally impose the
same pause on every other activity. An Agent that has created a large amount
of temporary data does not necessarily have to stop thousands of unrelated
conversations.

This does not make BEAM the fastest machine for every type of computation.
That is not the point. Its talent is keeping a system made of many independent
activities alive and responsive. For Agents, that is often more valuable than
winning a comparison based on one function running in isolation.

Message passing completes the picture. If a user adds new information while a
job is still active, the message can reach the process that owns the Agent. A
monitor can notice that a job has ended. A timer can wake a recurring activity.
A late response can be compared with the attempt that created it and rejected
when that attempt is no longer valid.

BEAM does not decide the rules of our Agent. It does give us one coherent
runtime language in which to express them. State, messages, time, and failure
do not feel like pieces from unrelated systems that we have to force together.

## Elixir makes this machine understandable

BEAM is the foundation, but Elixir is what made me want to build on it.

Pattern matching makes many transitions readable when they would otherwise
become a sequence of checks. Immutable data helps us see a transition as the
movement from one state to another instead of hiding changes inside shared
objects. Macros let us create a language for the problem without reducing the
whole behavior to strings inside a prompt.

That readability matters for an Agent. A programmer should be able to read its
behavior. It should be clear which event activates it, which job it starts,
and which action requires authority. Elixir makes it possible to write code
that stays close to the idea it describes while remaining code that the
runtime can verify.

Then there is the ecosystem. Elixir is already strong when a system needs HTTP
connections, databases, streaming, telemetry, and realtime interfaces. With
[Nx](https://hexdocs.pm/nx/Nx.html) and
[`Nx.Serving`](https://hexdocs.pm/nx/Nx.Serving.html), it can also handle
tensors, inference, and batching. Some classifiers, embeddings, and
models can therefore live directly inside BEAM.

I do not believe the value of Elixir depends on replacing Python. Python and
CUDA remain excellent tools for training models and performing heavy numerical
work. Elixir can coordinate a Python service, a local GPU, or a remote provider
without handing ownership of the Agent to any of them.

BEAM also has real limits. Long computation that occupies the CPU can reduce
responsiveness. A poorly written native function can block schedulers that
should be serving other processes. A mailbox can grow too large when nobody
has limited the pace of incoming messages. Distribution between nodes does not
automatically solve security, consistency, or network problems.

Those limits do not weaken the choice. They make it clearer. BEAM is an
excellent place to manage the lifecycle and coordinate the work. Specialized
computation can stay where it runs best.

## Why Spectre is written in Elixir

This is exactly the reasoning that led me to choose Elixir for
[Spectre 0.3.2](https://github.com/elchemista/spectre/tree/0.3.2).

I did not want to build another container around a prompt. I wanted a runtime
where an Agent had an identity, state, and lifecycle that did not depend on the
mood of the model. In Spectre, an Instance owns canonical state. Jobs can start
and be observed without becoming the owners of the Agent. An Effect can
describe an action, but Policy and the host decide whether that action may
actually cross the boundary into the outside world.

Many of these ideas began with control and safety, but OTP gave them a natural
shape. It kept bringing me back to the right questions. Who owns this state?
Who supervises this process? What happens when the result arrives too late?
Which part can fail without corrupting the rest?

When I think about choosing Elixir today, syntax and performance are not the
first things that come to mind. I think about the way BEAM forces the system to
have visible boundaries.

BEAM was not built for artificial intelligence. It knows nothing about
prompts, models, or Agents. It was built to keep concurrent systems alive
while some of their parts fail.

But the moment an Agent stops being a demo and has to stay alive in the real
world, it begins to have exactly that problem.

That is why Elixir feels less like a strange choice for serious Agents every
day, and more like the right one.
