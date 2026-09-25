# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

M321_TBZ_Phaseolus_Express is a school project (module M321, TBZ) demonstrating a simple microservice architecture. This repo, **Phaseolus Central**, is the meta/orchestration repo: it uses Kubernetes (via minikube) to spin up pods built from images produced by the separate service repos below.

**Phaseolus Express** is the product wrapped around this architecture: a webapp for ordering bean food. It intentionally has a whimsical/joke framing (bean puns) since the priority is the microservice plumbing, not the end-user features.

Services (each its own repo, referenced/orchestrated from here):
- **BeanApp** — order handling (`Phaseolus_WebApp`)
- **OrderBeans** — order handling (`Phaseolus_Order`)
- **PayBeancoins** — payments (`Phaseolus_Payment`)
- **CookerBeaners** — order fulfillment/kitchen (`Phaseolus_Cooker`)
- **BeanNotifs** — notifications (`Phaseolus_Notifs`)

Infrastructure:
- **Message Broker:** RabbitMQ
- **Orchestration:** Kubernetes
- **Clustering:** minikube
- **API Gateway:** Traefik
- **IAM:** Keycloak
- **Metrics/Monitoring:** Prometheus and Grafana
- **CI/CD:** Argo CD

### Project Goals

The assignment requires a microservice architecture covering: a message broker, IAM, metrics/monitoring, and deployment/orchestration. The core grading criterion is **functionality and operation between systems** (service-to-service communication, orchestration, auth, observability, deployment pipeline) — not the feature set exposed to end users. The online-ordering/shop domain (order → pay → cook → notify) was chosen specifically because it naturally decomposes into independent services that communicate via the message broker, giving a realistic surface to demonstrate the required infrastructure.

## Behavioral Guidelines

Guardrails to reduce common LLM coding mistakes. **Tradeoff:** these bias toward caution over speed — for trivial tasks, use judgment.

### 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

### 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines, and it could be 50, rewrite it.

Ask: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

### 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it — don't delete it.

When your changes create orphans:
- Remove imports / variables / methods / routes that *your* changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: every changed line should trace directly to the user's request.

### 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → write unit tests examples for invalid inputs, then make them pass.
- "Fix the bug" → write a unit test that reproduces it, then make it pass.

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** diffs contain fewer unnecessary changes, fewer rewrites follow overcomplication, and clarifying questions come *before* implementation rather than after mistakes.

## Branch discipline

**Never switch branches or create a new branch without explicit user confirmation.** This is non-negotiable.

- Do **not** interpret short replies like "go", "proceed", "continue" as authorisation to switch branches or create new ones. They authorise execution on the current branch only.
- If a plan or task seems to logically call for a new branch (sibling feature, separate PR), **ask first** — name the branch you'd create, explain why, and wait. The cost of a one-line confirmation is low; the cost of committing on the wrong branch is high (lost context, wrong PR target, manual recovery).
- Always check `git rev-parse --abbrev-ref HEAD` before committing and confirm with the user that this is the intended branch.
- If you find yourself on what looks like an unrelated branch (e.g. the branch name doesn't match the work), **stop** and ask — don't assume it's safe to commit anyway, and don't switch branches "to clean things up". The user may be intentionally using that branch.



