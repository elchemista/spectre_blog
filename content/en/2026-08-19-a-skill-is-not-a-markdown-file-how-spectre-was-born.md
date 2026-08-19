---
title: "A Skill Is Not a Markdown File: The Reasoning That Led Me to Spectre"
slug: "skill-is-not-markdown-file-how-spectre-was-born"
lang: "en"
status: published
date: 2026-08-19
updated: 2026-08-19
category: "Software Development"
tags: ["AI agents","skills","Spectre","Elixir","pattern recognition","routing","Morph","agent governance"]
seo_title: "Beyond Markdown Skills: How Spectre Was Designed"
seo_description: "Skills are more than instructions. How patterns, Flow, Journal, Ledger, Lab, and Morph shaped the way Spectre recognizes, learns, and evolves."
cover_alt: "A pattern recognized by the Spectre runtime becomes a governed Skill through Flow, Journal, Ledger, Lab, and Morph"
---

When I started thinking about how to build an Agent, skills already existed.

Tools such as Codex, Claude, and other agent systems used skills built around
Markdown instructions, sometimes accompanied by scripts, tools, and other
resources. The system recognized that a particular skill might be useful,
loaded its instructions into the context, and let the model apply them.

It was a simple and powerful idea. Without training the model again, you could
explain how to use a tool, follow a company procedure, or approach a particular
category of problems.

Yet while building [Spectre](https://github.com/elchemista/spectre/tree/0.3.2),
I kept returning to one question:

> Is the Markdown file really the skill, or is it only the manual that
> describes the skill?

To answer it, I started with something we knew long before Large Language
Models: the way living beings learn.

## Before models, there were patterns

The human brain, like the brains of other animals, evolved to recognize
patterns.

An animal does not need a scientific understanding of a predator's shape,
speed, and trajectory. It only needs to recognize enough signals resembling
something encountered before to activate a response.

We work this way all the time too.

When we learn to drive, we initially have to think consciously about every
movement. We check the mirror, press a pedal, change gear, and watch the road
as almost separate operations. After enough experience, we no longer
reconstruct the entire theory of driving each time. We recognize a situation
and activate a procedure we have already practiced.

The same thing happens to an experienced programmer. Faced with a familiar
error, they do not read every character as if seeing it for the first time.
They recognize the shape of the problem and immediately begin narrowing down
its possible causes.

The brain does not preserve only a ready-made answer. It learns a relationship
between a situation, a possible behavior, and the result that followed.

In a highly simplified description, experience and neural plasticity
strengthen some connections and weaken others. Repetition, error, and feedback
gradually make it easier to activate a useful behavior when a similar
situation appears again.

That is why a human skill is not simply a memorized response. It is the
capacity to recognize when a procedure may be useful, apply it to the current
context, and correct it after observing the result.

First we recognize the pattern. Then we activate the behavior.

This idea became important to Spectre.

## How a Large Language Model learns

A neural network also learns from patterns, but it does so differently from a
biological brain.

A Large Language Model is a neural network based, in most modern cases, on the
Transformer architecture. During training it receives enormous quantities of
text and adjusts its parameters to become better at predicting which token
should follow the previous ones.

That may sound like a limited objective, but predicting language well requires
the model to learn an enormous number of regularities. It must recognize
grammatical structures, relationships between concepts, forms of reasoning,
coding conventions, writing styles, and procedures that recur in the training
data.

This knowledge is not necessarily stored in separate blocks. There is no
internal folder called "weather skill" or one isolated part of the model
dedicated to "writing Elixir code." Representations and behaviors emerge in a
distributed form across a vast number of parameters.

Attention helps the model determine which parts of its input matter in
relation to the others. The feed-forward networks inside Transformer blocks
transform those representations further. There is not, however, one attention
head that we can switch on to activate a skill deterministically.

When we place a skill in the prompt, we change the context guiding the model's
computation. The instructions influence its activations and therefore the
distribution of possible responses.

This means a Markdown skill does not normally teach the model's weights
anything new. It temporarily places a manual on the model's desk.

The model reads that manual, tries to connect it to the request, and uses the
abilities learned during training to execute the described procedure.

This mechanism is enormously useful. We can change a procedure without
training the model again. We can add examples, introduce new tools, and provide
knowledge specific to one company.

But it remains a manual.

The model still has to interpret it correctly every time.

This is where my reasoning began to take a different path.

## Why ask the model to do everything?

If recurring behavior begins with recognizing a pattern, why should the model
always be responsible for recognizing that pattern?

Imagine that a user writes:

> What is the weather in Como?

We can send the sentence to an LLM, ask it to understand the intent, let it
select the correct tool, call a weather service, and finally generate a
response.

It works. But we are using a general model to rediscover something the system
could already know.

The request contains a fairly simple pattern: the user wants weather data for
a particular location.

A regular expression can recognize some explicit forms. A classifier can
identify the intent. Vector similarity can connect different phrases to the
same meaning. If confidence is sufficient, the runtime can call the weather
API directly and return a formatted response.

We do not necessarily need an LLM to tell us that 18 degrees is 18 degrees.

This observation is not only about saving tokens. Removing an unnecessary
model call also gives us lower latency, a more predictable result, and behavior
that is far easier to test.

The situation changes, of course, when the user asks:

> Considering the weather in Como, Milan, and Lugano, which day would be best
> for an outdoor event?

Here the model can be genuinely useful. Spectre can collect the data
deterministically, structure it, and give the model only the task that requires
comparison, reasoning, and explanation.

The point is not to choose between code and artificial intelligence.

The point is to understand which part of the problem genuinely needs a model.

This line of thought led to `on` inside Spectre Flows and to
[evidence-first routing](https://github.com/elchemista/spectre/blob/0.3.2/docs/ROUTING.md).

~~~text
input
  ↓
pattern recognition
  ↓
Flow.on
  ├── deterministic behavior
  ├── specialized skill with a model
  └── general model as fallback
~~~

Before delegating everything to an LLM, Spectre can observe the input and try
to recognize a situation it already knows. It can do this with an explicit
rule, a regular expression, a classifier, or semantic search.

If the pattern is simple and the behavior has already been defined, Spectre
can execute it without a model. If reasoning is needed, it can prepare a much
more precise skill and context. If the request is new or ambiguous, it can
hand control to a general model or ask for clarification.

The model does not disappear.

It simply stops being the component forced to rediscover everything from
scratch during every interaction.

## Markdown skills become stronger

I never thought Markdown skills should disappear.

They are extremely useful when we need to describe a flexible procedure,
teach the model how to use a tool, or provide information that was unavailable
during training.

Spectre adds something around those instructions.

The runtime can decide when a skill should be used, which pattern activated
it, which model may execute it, which tools it may use, and which actions
require authorization.

The skill is no longer simply added to a prompt in the hope that the model
will interpret it correctly. It becomes a capability inside the Agent's
behavior.

Markdown can still describe the cognitive part of the procedure. The Flow
defines when it becomes active. Policies bound its authority. The runtime
observes its execution.

In this form, a skill is no longer only something the model has read. It is
something the Agent knows when and how to use.

## A system that learns from real cases

Regular expressions work well when language is predictable. Humans, however,
can express the same intent in completely different ways.

"What is the weather?", "Will it rain today?", "Do I need an umbrella?", and
"Can I go out without a jacket?" may require the same data without sharing the
same words.

This is where semantic similarity becomes interesting.

Spectre can preserve recognized examples and compare a new input with known
patterns. An administrator can observe how requests are classified, confirm
correct cases, and correct the wrong ones.

Over time, the system collects ways of expressing an intent that were not
anticipated when the Agent was first built and may not have appeared in the
model's training data either.

This does not necessarily require new fine-tuning.

We can improve the external recognition layer, add examples, adjust
thresholds, and make routing progressively more precise.

It is a different form of learning. The model's weights do not change, but the
Agent's operational capability does.

The system learns to recognize its real environment more accurately.

This matters especially in business applications because every company
develops its own language. Customers use internal names, abbreviations, and
recurring ways of describing problems that no general model can know
completely in advance.

Spectre makes it possible to transform this local experience into explicit
behavior.

## Recognizing a pattern without losing control

A classifier can be wrong. A regular expression can be too rigid, and two
semantically similar requests can carry very different operational intents.

But this is not a problem left to each final application or something every
Spectre user must solve from scratch.

Spectre was designed from the beginning around the idea that recognizing a
pattern is not absolute truth. It is evidence accompanied by a degree of
confidence. The router collects candidates from different sources, and the
arbitrator decides which evidence is strong enough to become a route.

The runtime therefore provides acceptance and margin thresholds, explicit
conflict handling, and control over the selected path. If recognition is not
safe enough, Spectre can avoid deterministic execution, ask for clarification,
or use a model as the final arbiter between routes that were already declared.

The most important part comes after the decision.

The [Journal](https://github.com/elchemista/spectre/blob/0.3.2/docs/JOURNAL.md)
stores structured records that explain what happened inside the runtime. It
can record collected evidence, scores, margins, configured thresholds, the
selected route, and the reason for the decision, while excluding conversation
content by default.

[Spectre Ledger](https://github.com/elchemista/spectre_ledger) does not
duplicate the Journal and does not claim to record every internal revision. It
stores, in append-only form, the checkpoints Spectre actually persists and the
boundary receipts emitted when the runtime crosses nondeterministic or
authority boundaries. It therefore provides durable evidence of what was
saved and which boundaries were crossed.

[Spectre Lab](https://github.com/elchemista/spectre_lab) brings those artifacts
into an isolated verification and testing environment. It can load and compare
verified checkpoints and boundary receipts, exercise streaming through
virtual fixtures, and inject controlled failures at persistence and receipt
boundaries. It does not pretend to deterministically recreate an old model
response or an external effect. Instead, it provides the tools needed to turn
an observed case into a repeatable test without reopening live I/O.

Spectre also offers route-only evaluation, which runs the routing pipeline
without loading Agent state and without executing the winning handler. A
misclassified case can therefore become a regression fixture before a new
configuration is promoted.

Spectre does not solve this problem by pretending recognition is infallible.

It solves it by making the decision explainable, the evidence persistable, and
the case verifiable.

That distinction matters. An error we can isolate and repeat can become a
test. An error hidden inside a conversation remains only a conversation that
went wrong.

## From many cases to a new capability

At this point, another question appeared.

What happens when a pattern keeps recurring?

At first, a general model may handle a new request. Then Spectre observes that
similar cases appear frequently. The administrator begins to recognize them,
corrects them, and discovers that they almost always lead to the same
procedure.

At that point we are no longer looking at a collection of conversations. We
are watching a new skill emerge.

This reasoning led to
[Morph](https://github.com/elchemista/spectre/blob/0.3.2/lib/spectre/morph.ex).

Morph can help a trusted host transform a recurring pattern into a candidate
capability. The pattern, procedure, and expected result can be analyzed,
tested, and eventually promoted into a new version of the Agent.

This idea resembles natural evolution in one respect.

In nature, characteristics that work better in a particular environment are
more likely to be preserved. In Spectre, however, evolution should not be
blind or uncontrolled.

It is observed and guided.

The model or Forge can discover a regularity and produce an inert proposal.
Morph can carry that change through evaluation, review, approval, and
activation. Promotion, however, remains an explicit action authorized by the
host.

The new capability enters a new immutable Agent Definition. The previous
version is not deleted and remains available for comparison or rollback.

The Agent can therefore evolve without losing its history and without giving
the model the authority to rewrite itself freely.

Experience does not simply become an ever longer prompt.

It becomes a recognizable pattern and versioned behavior.

## What, then, is a skill?

After following this path, I arrived at a different definition from the one I
started with.

A skill is not the Markdown file.

Markdown is one possible representation of the procedure, just as a manual is
a representation of something a person can learn to do.

The complete skill appears when a system can recognize the right situation,
activate the procedure, respect the limits of its authority, observe the
result, and use that experience to improve.

The model provides the capacity to generalize and reason. Spectre provides the
lifecycle, control, operational memory, and the ability to turn real cases
into explicit behavior.

I do not want to build an Agent that sends every problem to a general model and
hopes it will correctly interpret an ever larger manual.

I want to build an Agent that can distinguish what it already knows from what
genuinely requires reasoning.

When the pattern is simple, it can respond through deterministic behavior.
When the problem requires intelligence, it can activate the correct skill and
model. When it encounters something new, it can learn from experience without
changing outside human control.

To me, this is the most interesting direction.

A skill is not what we wrote for the model.

It is what the Agent has learned to recognize, knows how to execute, and can
continue improving without losing control.
