# Have the AI interview me and write a new step-by-step prompt template, ready to save in this collection

## 1. Introduction

In this session you will act as a prompt engineer. I keep a personal collection of reusable prompts for LLMs, and I want your help writing a new one. You won't do the task yourself: your job is to write the prompt that will make another AI session do it well.

The task I want a prompt for: [WHAT THE PROMPT SHOULD MAKE THE AI DO]
Where I'll use it: [TOOL OR CONTEXT, e.g. Claude Code inside a repo, claude.ai chat]
My rough notes or an existing draft (optional): [NOTES OR DRAFT]

## 2. Metaprompt instructions

Work through these steps in order, and wait for my OK before moving to the next one:

1. Understand: read my notes and ask me about whatever is missing. Ask at most 3-4 questions at a time, grouped by topic, and offer options with your recommendation when you can. Point out anything in my notes that is vague or contradicts itself.
2. Outline: propose the shape of the prompt as a short list: its sections, the steps the session will follow, and the slots I'll fill in each time I use it.
3. Draft: write the full prompt following the pre-made template in section 3.
4. Review: tell me the assumptions you made and the weak spots you see, then apply my changes.
5. Deliver: give me the final version in a single code block, together with its file name and category.

Rules for the prompt you write:
- Write it in first person, as if I were the one talking to the AI, using plain and easy-to-understand phrases.
- Put anything that changes between uses in [UPPERCASE SLOTS]. Keep the slots few and obvious.
- Explain the reason behind important instructions, not only what to do.
- Don't add rules I didn't ask for "just in case". Keep it as short as the task allows.
- File name: lowercase words joined by hyphens, ending in .md. If the prompt is for a specific project, start with the project name. Category: templates/ if it has slots, prompts/ if it's ready to send as is, scripts/ if it's shell commands.
- The first line of the file is a one-line description starting with "# ", saying what the prompt does in the same descriptive style as: "# Diagnose and fix a bug from a Jira ticket, with repro steps, crash location, callstack and hypothesis".

## 3. Pre-made template for the prompt you write

Use this structure, adapting or removing the parts that don't fit the task. The parts in {curly braces} are for you to write; the [UPPERCASE SLOTS] inside them are for me to fill in each time I use the prompt.

```
# {one-line description of what this prompt does}

This session will focus on {goal}. {context the AI needs: project, tools, constraints}

{the inputs for each run, as [UPPERCASE SLOTS]}
---

How to ask me things:
- {when to ask, e.g. before making design choices, or when my explanation conflicts with what you find}
- {how to ask, e.g. a few questions at a time, with options and your recommendation}

What to ask me about:
- {the topics where my input matters}

Steps for this session:
1. {first step, e.g. gather context or diagnose}, then {what to show me before continuing}
2. {next step}, then {checkpoint}
3. {final step, and what the finished result looks like}
```
