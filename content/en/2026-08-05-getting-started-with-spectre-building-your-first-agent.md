---
title: "Getting Started with Spectre: Your First Agent Is Not a Loop"
slug: "getting-started-with-spectre"
lang: "en"
status: published
date: 2026-08-05
updated: 2026-08-05
category: "Software Development"
tags: ["Elixir","OTP","AI agents","Spectre","agent runtime","getting started"]
seo_title: "Getting Started with Spectre in Elixir"
seo_description: "An introduction to Spectre: how to think about subjects, instances, runs and turns, and how to build your first agent without hiding the application behind a model."
cover_alt: "A first Spectre agent: a subject resolved by the host, an OTP instance owning state, and turns crossing a visible boundary"
---

Most agent tutorials start with a model call. You send a prompt, describe two tools, print the answer, and the demo works.

Spectre asks you to start somewhere else.

Before choosing a model, you have to answer a much less exciting question: **who owns the state?** Once that answer exists, everything else in the runtime becomes ordinary Elixir. If it does not exist, you end up with a conversation transcript pretending to be an application.

So this is an introduction, but not the kind that produces a chatbot in twenty lines. It is the shortest path I know to an agent you can still debug in three months.

## The one idea you need first

If you take a single sentence from this post, take this one.

> **The module that uses `Spectre.Agent` is not the living agent. It is the compiled definition of the agent.
> The living agent is a `Spectre.Instance`, identified by `AgentRef + Subject`.**

The module declares routing, flows, policies, actions, memory and persistence. It is a readable map of behaviour. The `Instance` is the OTP process that holds the ordered state of the relationship between that agent and one specific subject.

Your real logic still lives in normal Elixir modules. Spectre is not asking you to move your domain into a DSL; it is asking you to stop scattering lifecycle decisions inside it.

Here is the vocabulary, once, so the rest of the post reads quickly:

| Object         | Meaning                                                                     |
| -------------- | --------------------------------------------------------------------------- |
| `Agent`        | The definition: what it can do, how it routes, which policies apply         |
| `Subject`      | The canonical person or entity the agent works with                         |
| `Instance`     | The OTP owner of state for `Agent + Subject`                                |
| `Input`        | A normalised message                                                        |
| `Input.Source` | Where that message came from: web, chat, an MCP client                      |
| `State`        | Authoritative state: flow cursor, data, policies, effects, history          |
| `Run`          | One logical execution produced by an input                                  |
| `Turn`         | What you receive when the Run reaches an observable boundary                |
| `Effect`       | An external operation that has been proposed, not necessarily executed      |
| `Work`         | A precise, durable procedure independent of the chat                        |
| `Vigil`        | A recurring, durable observation                                            |

## The subject is the part people get wrong

A `Subject` is not a chat ID, a phone number or a conversation ID. It is the canonical application identity: `{:user, 42}`, `{:company, 18}`, `{:boat, "IT-123"}`.

The channel does not disappear, it simply belongs somewhere else — inside `Input.Source`. That separation is what lets the same person talk to the same agent from a website and from a chat app while keeping one continuous state, provided your host authenticated and linked those identities on purpose rather than by accident.

The whole shape of an integration is this:

```text
web / chat / MCP client
          │
          ▼
   host authentication
          │
          ▼
 external identity → Subject
          │
          ▼
Agent + Subject → Spectre.Instance
          │
          ▼
  Spectre.turn(instance, input)
          │
          ▼
        Run → Turn
          │
 reply / policy / effect / completion
```

Nothing in that diagram is negotiable in Spectre, and nothing in it involves a model yet.

## A conversation is many runs over one state

This is the second thing that surprises people.

A Spectre conversation is not one long run that stays open while the user types. Normally every message creates a **new** `Run`, and all of those runs read and mutate, in order, the same `State` owned by the instance.

```text
Instance
└── shared State
    ├── Run 1
    ├── Run 2
    └── Run 3
```

So a three-step wizard looks like this:

```text
State revision 0 — current_flow: nil

User: "create project"
    └── Run R1 → Turn: "What is it called?"
        State revision 1 — current_flow: :project_name

User: "Spectre Studio"
    └── Run R2 → Turn: "What is the goal?"
        State revision 2 — current_flow: :project_goal

User: "Managing durable agents"
    └── Run R3 → Turn: "Confirm?"
        State revision 3 — current_flow: :project_review
```

Continuity does not come from keeping R1 alive. It comes from `state.current_flow`, `state.current_scope` and `state.data`.

There is exactly one important exception. When a run stops because it is waiting for a policy decision, the pending effect belongs to **that** run. Spectre uses the conversation origin in `Input.Source` to correlate the answer back to it. If several policies are open and the origin is ambiguous, you get an explicit error rather than a lucky guess.

> **Normal wizard: new runs sharing one state.
> Suspended policy: correlated resumption of the owning run.**

That single rule explains most of the runtime's behaviour.

## Start with the core, and with no model at all

The temptation is to wire up a model on day one. I would not.

Add the dependency, pinned to a commit you actually verified, since the API is still young:

```elixir
defp deps do
  [
    {:spectre, github: "elchemista/spectre", ref: "<verified-commit-sha>"}
  ]
end
```

Then put the supervisor in your tree:

```elixir
def start(_type, _args) do
  children = [
    {Spectre.Supervisor, name: MyApp.SpectreSupervisor},
    MyApp.Repo,
    MyAppWeb.Endpoint
  ]

  Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
end
```

`Spectre.Supervisor` starts and finds the instance that is unique for an `Agent + Subject` pair. Two concurrent requests for the same pair converge on the same instance; different subjects get completely independent state.

Your first agent should be boring and deterministic:

```elixir
defmodule MyApp.SupportAgent do
  use Spectre.Agent, history: 30

  router(via: [:regex])

  interrupt :HELP, regex: ~r/^(help|menu)$/iu do
    reply(:help, renderer: {MyApp.AgentReplies, :render})
  end

  flow :main do
    on :HELLO, regex: ~r/^(hi|hello)$/iu do
      reply(:hello, renderer: {MyApp.AgentReplies, :render})
    end

    on :ACCOUNT_STATUS, regex: ~r/^account status$/iu do
      run(:account_status)
    end
  end

  def account_status(input, context) do
    account_id = Keyword.fetch!(context.opts, :account_id)
    account = MyApp.Accounts.fetch!(account_id)

    {:ok,
     %Spectre.Result{
       input: input,
       route: context.route,
       state: context.state,
       reply_text: "Account status: #{account.status}"
     }}
  end
end
```

`reply/2` returns something fixed. `run/2` calls ordinary Elixir, and `MyApp.Accounts` keeps owning the domain. The agent module stays a map of behaviour rather than a place where business rules go to hide.

What you are verifying at this stage has nothing to do with intelligence: that the subject is right, that the instance is reused, that turns are produced, that state advances, and that a reply is delivered exactly once.

## Resolving the subject and finding the instance

The gateway decides who is speaking:

```elixir
subject = Spectre.Subject.new({:user, user.id}, metadata: %{tenant_id: user.tenant_id})

{:ok, instance} =
  Spectre.ensure_instance(
    MyApp.SpectreSupervisor,
    MyApp.SupportAgent,
    subject,
    idle: :timer.minutes(30)
  )
```

Call `ensure_instance/4` on every message. You do not need to keep a PID in a socket or a LiveView, because the runtime identity is the logical pair, not the process:

```text
MyApp.SupportAgent + Subject(user:42)
```

The PID changes after a restart. The pair does not.

Then build a real input, with its origin attached:

```elixir
input =
  Spectre.Input.new(%{
    text: message.text,
    meta: %{locale: user.locale},
    source: %{
      kind: :web,
      mount: :support_chat,
      conversation_id: message.thread_id,
      actor_id: user.id,
      reply_to: message.id,
      metadata: %{}
    }
  })

{:ok, turn} = Spectre.turn(instance, input, account_id: user.account_id, user_id: user.id)
```

You can pass a plain string while experimenting, but the source is what later lets the runtime match a plain “yes” to the right pending policy in the right conversation. It is cheap to add now and painful to retrofit.

Internally the cycle is unremarkable, which is the point:

```text
normalise input → load state → maybe resume a policy
→ collect routing evidence → pick a route → run the handler
→ update history → commit state → return the turn
```

The run stops at the first observable boundary instead of hiding routing, approval and execution inside one call.

## The turn is the whole API surface you consume

For application code, `turn.decision` is almost everything:

```elixir
case turn.decision do
  {:reply, result} ->
    MyApp.Chat.send(thread_id, result.reply_text)

  {:awaiting, _awaitable, result} ->
    MyApp.Chat.send(thread_id, result.reply_text)

  {:needs, effect, result} ->
    MyApp.Effects.enqueue(effect, result)

  {:completed, completion, result} ->
    MyApp.Audit.record(completion, result)

  {:no_response, result} ->
    MyApp.Audit.record_silent_turn(result)
end
```

| Decision                           | Meaning                                      |
| ---------------------------------- | -------------------------------------------- |
| `{:reply, result}`                 | You have text to deliver                     |
| `{:awaiting, awaitable, result}`   | An input or a policy decision is required    |
| `{:needs, effect, result}`         | The effect is authorised and can be executed |
| `{:completed, completion, result}` | The operation finished                       |
| `{:no_response, result}`           | The turn ends with no visible output         |

Rather than repeating that `case` in every channel, implement a dispatcher once:

```elixir
defmodule MyApp.AgentDelivery do
  @behaviour Spectre.Turn.Dispatcher

  @impl true
  def deliver_reply(text, _result, opts) do
    MyApp.Chat.deliver(Keyword.fetch!(opts, :conversation_id), text)
  end

  @impl true
  def execute?(effect, _result, opts) do
    MyApp.Authorization.allow_effect?(Keyword.fetch!(opts, :user_id), effect)
  end

  @impl true
  def suppressed(_effect, _result, opts) do
    deliver_reply("You are not authorised to perform this operation.", nil, opts)
  end
end
```

One warning worth repeating: the default of `execute?/3` is `true`. For any agent that owns a sensitive action, implement the veto and re-check authorisation at the real application boundary.

## Approval is not execution

This is where Spectre stops looking like a chat library.

A `run/2` handler can read data and compose a reply. When you want to cross an external boundary — delete, publish, send, pay — you declare an action and protect it:

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

The first message produces `{:awaiting, awaitable, result}`. The effect exists, it is waiting on the policy, and `delete_account/2` has not been called.

The confirmation produces `{:needs, effect, result}`. The effect is now approved — and still not executed. Only your dispatcher or host crosses that line.

The action receives an `effect_id` and an `idempotency_key`, and that key must be written in the same transaction as the real operation. An ETS check is not a defence against a crash.

Three states that most agent frameworks collapse into one — proposed, approved, executed — stay visibly distinct here. That is the whole reason I would trust this runtime with something more serious than drafting text.

## Where you actually look when it misbehaves

Not the chat history. History is conversational context; it is not the machine state.

When an agent does the wrong thing, read in this order:

```text
turn.result.input.text
turn.result.route.label
turn.result.state.revision
turn.result.state.current_flow
turn.result.state.current_scope
turn.result.state.awaitables
turn.result.state.pending_effects
turn.result.state.trace
turn.ref
Spectre.Instance.info(instance)
```

`Instance.info/1` gives a privacy-safe operational view, and `Instance.run/2` returns a compact view of a run or of its tombstone. The `Run.Ref` token is also the natural idempotency key for delivery:

```elixir
delivery_key = Spectre.Run.Ref.token(turn.ref)

MyApp.Deliveries.deliver_once(delivery_key, fn ->
  MyApp.Chat.send(conversation_id, turn.result.reply_text)
end)
```

Log the run token, the decision kind, the route label and the state revision for every turn. Those four fields answer most production questions without opening a debugger.

## A wizard needs one more piece than you expect

Setting `current_flow` does not magically make arbitrary text land in the right step. When the user answers `Spectre Cloud`, that string carries no classifiable intent at all.

So a correct multi-step conversation is:

```text
a normal initial route
+ State.current_flow and State.current_scope
+ State.data holding the draft
+ a deterministic continuation router plug that reads the cursor
+ a global cancel/help interrupt
+ an explicit clear when the workflow ends
```

The continuation plug reads the cursor, finds the exact rule matching it, preserves global interrupts and explicit commands, drops the normal candidates that would otherwise steal the answer, and adds one deterministic candidate. The capture routes stay invisible to ordinary routing, so a random message can never be classified as “project name”.

And when the workflow finishes, clear the cursor yourself:

```elixir
%{context.state | current_flow: nil, current_scope: nil,
                  data: Map.delete(context.state.data, :project_draft)}
```

Forgetting that line is, in my experience, the single most common way to build an agent that feels haunted.

## Persistence, and the difference between two levels

Conversational state is a `%Spectre.State{}`: flow cursor, wizard data, open policies, effects, history, revision. Store it with compare-and-swap, never with a blind write:

```sql
UPDATE spectre_agent_states
SET payload = ..., revision = revision + 1
WHERE agent_id = ... AND subject_id = ... AND revision = expected_revision
```

If no row was affected, you have a conflict, and an older turn must not overwrite newer state.

The second level is the instance checkpoint, which is what you need once retained runs, `Work`, `Vigil` and scheduling exist. An ambiguous commit there creates a persistence fence and is not retried automatically, because it is never safe to assume the previous write did not happen.

That reluctance to guess is deliberate. A crash is not proof that nothing happened.

## Conversation, work and observation are different things

A flow answers the current conversation. A `Work` runs a finite procedure that outlives the turn that started it:

```elixir
on :START_RESEARCH, regex: ~r/^research\s+.+$/iu do
  work(MyApp.ResearchWork, input: :text, origin: :chat, reply_text: "Research started.")
end
```

The chat turn ends immediately. The work continues, and you can inspect it, pause it, update it, or express update-and-resume as one durable intention:

```elixir
{:ok, resumed} =
  Spectre.Instance.update_and_resume_loop(instance, work_ref, %{extra_urls: urls})
```

This is how “I changed my mind while it was running” becomes a real transition instead of another sentence appended to a prompt. A `Vigil` covers the third case: recurring observation that wakes, checks, commits and waits again.

The conversation, the finite operation and the durable observation share one instance without merging into one loop.

## The order I would actually follow

Build the minimal agent: one subject, one instance, three regex routes, one gateway, one dispatcher. Confirm that five messages from the same subject reach the same instance.

Then observe turns, and confirm that two normal messages produce two runs with consecutive revisions of one state.

Then add exactly one protected action, and confirm that the first turn is `:awaiting`, that the action was not called, that “no” cancels, that “yes” yields `:needs`, and that the action executes once with its idempotency key stored.

Then the wizard, with the continuation plug and the cancel interrupt. Then persistence with compare-and-swap and a restart test.

Only after all of that would I introduce a model, and even then for a single reasoning route — not yet to choose actions.

Before you call the first agent finished, these should hold:

| Scenario                             | Expected result                      |
| ------------------------------------ | ------------------------------------ |
| Same agent + same subject            | Same instance                        |
| Same agent + different subject       | Isolated state                       |
| Two normal messages                  | Two runs, ordered revisions          |
| Wizard on the second message         | Route determined by `current_flow`   |
| Cancel interrupt during the wizard   | Workflow cleared                     |
| Policy answered from the same chat   | Correct run resumed                  |
| Policy answered from another chat    | No accidental approval               |
| Two open policies, ambiguous origin  | Explicit error                       |
| Duplicated webhook                   | Reply delivered once                 |
| Retried effect                       | Operation performed once             |
| Restart during the wizard            | State restored                       |
| Old result after a new revision      | Result rejected                      |

## What you are really learning

Getting started with Spectre is not about the first reply appearing in a terminal. It is about being able to answer six questions at any moment:

```text
Who is the subject?
Who owns the state?
Which source did the message come from?
Which run produced this turn?
Is the result a reply, a policy or an effect?
Who is authorised to execute the effect?
```

A first agent that answers all six is small — one agent, one subject per user, one instance per pair, three routes, one wizard, one protected action, one dispatcher, one state store with CAS. It is also, in my experience, enough to understand almost the entire runtime, because everything larger is layered on the same cycle:

```text
Input → Instance → Run → State → Turn → host boundary
```

The model can join later, and it will be genuinely useful when it does. But it joins an application that already has a shape, which is the opposite of the way most agents get built.

Spectre is available on GitHub at [github.com/elchemista/spectre](https://github.com/elchemista/spectre).
