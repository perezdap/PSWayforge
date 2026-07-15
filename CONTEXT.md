# Domain Glossary: PSWayforge

## Module
PSWayforge itself: a PowerShell 7.3+ module that bootstraps agent-agnostic project workspaces.

## Project
The target directory being scaffolded.

## Workspace
The result of scaffolding: a Project containing `AGENTS.md`, `.agents/`, `.workflow/`, and supporting files.

## Skill
A reusable agent capability, documented in `.agents/skills/<name>/SKILL.md`.

## Workflow
A YAML-defined state machine in `.workflow/definitions/<name>.yaml`.

## Step
A single state in a workflow, such as `scout`, `plan`, or `build`.

## Hook
A lifecycle script in `.workflow/hooks/` invoked by agents or module utility functions.

## Capability
What an agent can do, e.g., `locate-context`, `generate-plan`.

## Agent
An AI system such as Claude, Kimi, Codex, Cursor, or a local LLM.

## Artifact
A JSON file passed between workflow steps.

## Schema
A JSON Schema defining an artifact's shape.

## Prompt
A system prompt template associated with a capability.
