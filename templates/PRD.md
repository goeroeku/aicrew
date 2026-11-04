# PRD — {{project name}}

Status: {{draft | approved by owner on YYYY-MM-DD}}

## Problem and users
{{who, what problem, why now — max 5 lines}}

## Goals and non-goals
- Goals: {{measurable outcomes}}
- Non-goals (intentionally out of scope): {{...}}

## Requirements
Each requirement has a permanent ID and machine-testable or observable acceptance criteria.

| ID | Requirement | Acceptance criteria (checkable) | Priority |
|---|---|---|---|
| R1 | {{...}} | {{test/command/page that proves it}} | {{must/should}} |

## Journeys
What a user can accomplish, in language a lead understands. Each journey becomes one epic during breakdown.
One requirement may serve more than one journey.

| ID | Journey | Requirements (R-ID, N-ID) | Done when |
|---|---|---|---|
| J1 | {{user can sign in with SSO}} | {{R3, R4}} | {{observable outcome}} |

## Non-functional requirements
| ID | Requirement | Acceptance criteria (checkable) | Label |
|---|---|---|---|
| N1 | {{login responds in < 1 s}} | {{load test / measurement}} | {{needs-perf / needs-security}} |

## Abuse cases and limits
Every endpoint or job that accepts outside input has one row. "None" needs a reason. Issues in the unbounded-input classes test these limits in their acceptance criteria.
| Endpoint/job | Max size | Max time | Max rate | Max memory | Behavior at the limit |
|---|---|---|---|---|---|
| {{POST /upload}} | {{10 MB}} | {{5 s}} | {{10/min per user}} | {{256 MB}} | {{reject with 413, no crash}} |

## Constraints
Stack, performance, security/authorization, data, cost, deadline: {{...}}

## Risks and hard-to-reverse decisions
{{DB schema, API shape, auth, money — flag items that need `needs-principal`}}

## Open questions
{{list; empty before status is approved, or explicitly mark as accepted}}

## Issue map (filled in by breakdown)
{{R-ID / N-ID → #issue, wave, journey (J-ID → #epic)}}
