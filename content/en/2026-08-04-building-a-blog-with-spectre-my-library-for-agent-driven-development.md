---
title: "Building a Blog Agent with Spectre, Not Around a Magic Loop"
slug: "building-a-blog-agent-with-spectre"
lang: "en"
status: published
date: 2026-08-04
updated: 2026-08-04
category: "Software Development"
tags: ["Elixir","OTP","AI agents","Spectre","agent runtime","Git-backed blog"]
seo_title: "Building a Blog Agent with Spectre"
seo_description: "How I built a Git-backed blog agent with Spectre, keeping model reasoning flexible while flows, state, publishing, and recovery remain explicit."
cover_alt: "A blog agent built around an explicit OTP runtime, connected to Markdown files, Git history, model reasoning, and controlled publishing"
---

I did not build Spectre because calling an LLM from Elixir was difficult.

That part is easy. Send a request, pass some messages, describe a few functions and wait for the model to return a tool call.

The problem starts after the first successful demo.

You give the model a goal. It decides what to do next, calls a tool, reads the result and decides again. It looks great in the terminal. Then you add memory, retries, approval, background work and another model call to judge whether the first model call did the right thing.

Before long, the application starts to feel like a shell around one large, intelligent loop.

I have nothing against that intelligence. I want the model to understand loose requests, read documentation, connect ideas and make decisions that would be painful to express as ordinary rules.

What bothered me was losing the shape of the software around it.

When something was running, I wanted to know what it was. When the user changed the request, I wanted to update the work rather than throw another message into the context. When an external call timed out, I wanted the application to admit that the result was uncertain. And when the process restarted, I did not want recovery to mean asking the model to reconstruct the situation from a conversation transcript.

I wanted the model, but I also wanted the flow.

That is the reason Spectre exists.

## The blog I am actually building

The blog is deliberately simple.

Articles are Markdown files. Git keeps the history. The application renders and publishes them. There is one editor agent, not a group of agents pretending to be a small media company.

I can talk to that agent through Telegram or through an MCP client. I might ask:

> Prepare an article about the new Spectre runtime. Read the repository first, use the same tone as the other posts, and leave it as a draft.

This looks like one request, but it is not one kind of work.

Part of it is conversational. The agent has to understand what I mean and decide how to respond. Part of it is operational. Reading sources, collecting notes and preparing a draft may continue beyond the original message. Publishing is something else again: it changes the repository and should not happen just because the model believes the article is ready.

A lot of agent systems place all of that inside the same loop.

Spectre separates it.

```text
Telegram or MCP
       │
       ▼
  Editor Agent
       │
       ├── Flow: understand the conversation
       │
       ├── Work: research and prepare the article
       │
       ├── Policy: require approval to publish
       │
       └── Vigil: watch published articles over time
```

The model can participate in every part where reasoning is useful, but it does not own the entire sequence.

## Conversation is not background work

In Spectre, a `Flow` handles the conversational side of an agent.

It describes the routes the agent understands and what those routes are allowed to start or propose. Routing can be strict where I need it to be strict, and flexible where natural language matters.

A direct command such as “publish this article” can use a deterministic match. A less predictable request can go through embeddings, a classifier or an LLM choosing between routes that already exist.

The important detail is that the model chooses within the application’s vocabulary. It does not invent a new part of the system whenever it needs one.

A conversation also has a recoverable continuation, represented by a `Run`. It may stop because the agent replied, because it needs more information, or because it reached an approval or execution boundary. That boundary is visible to the host application instead of being hidden somewhere inside another model iteration.

Researching and preparing the article is different.

That belongs in a `Work`: a durable, finite operation with its own state, progress, budget and completion condition.

This distinction sounds obvious when written down, but it changes how the application feels. The chat does not need to remain open while the article is being prepared, and the Work does not have to pretend that every operational step is another turn in a conversation.

It also means I can ask the agent what is happening without relying on the model to narrate its own hidden process.

> **Me:** How is the Spectre article going?

> **Agent:** I have read the core architecture and operations documentation. The comparison section is still missing.

That answer can come from the committed state of the Work: its phase, progress and published partial results. It does not have to be an improvised explanation generated from whatever context still fits inside the model window.

## Changing the request without starting again

The useful part comes when I interrupt the work.

Suppose the research has already started, and then I send another message:

> Include the reason I separated Work from Directive. Also use the new runtime document, not the old concept file.

The easy implementation is to append that sentence to the conversation and hope the next model call notices it.

Spectre treats it as a change to the running operation.

The agent can resolve which Work I am talking about, pause it at a safe boundary, apply an update and resume it with a new context revision. The update is limited to fields that the Work explicitly allows to change, and it keeps the provenance of the message that caused it.

This matters because the previous attempt may still finish later.

Without a revision boundary, an old result can arrive after the update and quietly move the article back toward the old requirements. In Spectre, that result belongs to an older view of the Work and can be rejected.

The model still performs the interesting part. It understands that my message changes the editorial direction and turns it into useful information for the operation.

But “the requirements changed” is no longer only a sentence in a prompt. It becomes a real transition in the application.

That is the balance I was missing elsewhere.

## The model is allowed to think

Spectre is not an attempt to turn an AI agent into a traditional workflow engine.

I do not want to describe every possible thought in advance. If I could do that, I probably would not need the model.

While preparing the article, the model may decide which parts of a source are relevant, compare different explanations, extract claims or choose the best structure for the draft. Spectre Prism can select a cheaper model for classification and a stronger one for writing or deeper reasoning. Spectre Lens can provide browser capabilities without making the browser itself part of the agent’s canonical state.

The point is not to make every decision deterministic.

The point is to be precise about which decisions are probabilistic.

The model can decide that a section is weak and needs more research. It can propose another declared operation. It can produce a revised outline. What it cannot do is quietly redefine the lifecycle around the work, grant itself a new capability or turn a suggestion into an external side effect.

Spectre does not try to control the model’s reasoning.

It controls what that reasoning is allowed to become.

## Publishing is where the difference becomes visible

Drafting text is relatively safe. Publishing it is not the same thing.

Publishing modifies the Git repository and makes the article visible. Depending on the application, it may also trigger a deployment, notify subscribers or send the content to other channels.

I do not want “the model called the publish tool” to be the complete security model.

In Spectre, the agent can propose publication, but a protected action enters an explicit policy lifecycle. The application can request confirmation, accept or reject a declared answer, limit the number of attempts and cancel the pending action.

Approval and execution are separate.

That separation is important. Confirming an action changes its state; it does not secretly perform the action in the same callback. The host application still crosses the real boundary and performs the Git operation using its own credentials and authorization rules.

So the interaction can remain natural:

> **Agent:** The draft is ready. Do you want me to publish it?

> **Me:** Publish it.

But underneath that small exchange, the model has not simply decided that the words “publish it” are enough to run arbitrary code. The response resolves a specific pending policy for a specific Effect. Only then can the host execute the registered capability.

This is what “human in the loop” should mean to me.

Not a note in the system prompt telling the model to be careful. Not a second model reviewing the first one. A real boundary in the runtime.

## A timeout is not a failed publication

External operations are where agent demos usually become normal distributed systems.

Imagine the application sends the Git commit or publication request and the connection disappears before the response comes back.

Maybe nothing happened.

Maybe the article was published successfully and only the response was lost.

Retrying automatically might be correct, or it might create a duplicate operation. Reporting failure might also be wrong.

Spectre does not assume that a crash proves the external action never happened. Operations describe the kind of side-effect boundary they cross. When an outcome can be reconciled, the runtime can ask the application to check what really happened before trying again.

This is not a particularly glamorous feature. It will not make an impressive five-second video.

It is one of the reasons I can imagine using the same runtime for actions more serious than writing a draft.

## Why OTP matters here

Spectre is OTP-native because the actor model already gives us a good answer to one of the hardest questions in an agent system: who owns the state?

For a running agent, Spectre uses a subject-scoped `Instance` as the canonical local owner. The Subject is the application identity being served: an account, a workspace, a customer or another real domain entity. It is separate from a Telegram chat ID, an MCP connection or any other channel identity.

The Instance owns the ordered conversational and operational state for that Subject.

Slow work does not happen inside its mailbox. A temporary Runner receives a fenced snapshot, performs one registered attempt, returns data and terminates. The Runner cannot commit canonical state by itself. The Instance validates the result and decides whether it still belongs to the current revision.

This keeps the state ownership simple without forcing every model call, browser request or external operation to block the agent process.

It also gives failure a clear meaning.

If a Runner crashes, one attempt failed. The Work still exists.

If the application restarts, the checkpoint contains portable state and stable identifiers, not old PIDs or live model clients. Runtime dependencies are resolved again, and stale results from before the restart cannot casually commit into the recovered agent.

That is much closer to how I expect an Elixir system to behave.

## Watching the article after publication

Once the article is published, the original Work is complete.

But the blog may still need to watch it.

A new Spectre release might make a paragraph outdated. A source could disappear. A link could start returning an error.

That is not another Work pretending never to finish. Spectre represents recurring observation with a `Vigil`.

A Vigil wakes on a timer or event, performs an observation, commits the result and waits again. It does not need to keep a live worker around between checks. If it finds something significant, that event can return through the agent’s normal Flow and eventually reach me through the appropriate channel.

The distinction remains the same: one abstraction for a finite operation, another for durable observation, and the conversation is still its own thing.

They share the same runtime without becoming one giant loop.

## What feels different

The finished blog agent is not less intelligent than one built around a fully model-driven loop.

It can still understand a loose request, search documentation, revise an article and adapt when I change direction. In places where a stronger model produces better work, I can use one.

What feels different is that I can still see the application around it.

I know which state is canonical. I know whether I am looking at a conversation, a finite Work or a recurring Vigil. I know when the model is choosing and when deterministic policy takes over. I can pause an operation, update it, resume it and inspect its committed progress. I know that approval does not execute a side effect, and that a timeout does not automatically mean it is safe to repeat one.

Spectre is not designed to make the model disappear behind rigid code.

It is designed to stop the rest of the software from disappearing behind the model.

That is what I wanted from an agent runtime: enough freedom for the model to be genuinely useful, with enough structure that building the agent still feels like building a system.

Spectre is available on GitHub at [github.com/elchemista/spectre](https://github.com/elchemista/spectre).
