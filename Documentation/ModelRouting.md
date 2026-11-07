# Model routing standard

Reusable reference for choosing a coding model per task. IssueCapture exports a
condensed copy at the top of every PDF/text handoff; this is the full standard.
Issues carry three optional reporter fields: **difficulty** (1 trivial – 4 epic),
**importance** (1 nice-to-have – 4 critical; independent of difficulty) and a
**suggested model**. Agents should group issues by suggested model, then order by
importance and difficulty, and delegate each group to that model.

## Tiers

| Tier | Model | Best for |
|---|---|---|
| Top (logic) | **Fable 5.1**, **GPT-6 Astra** | Hardest logical reasoning, architecture, gnarly debugging. Not for creative/design/taste work. |
| Top (creative) | **Opus 5.5** | Creative and 3D design, any design, taste, storytelling, "right-brain" work. Also strong at logic, but backend logic and checking usually go to Sol. |
| Upper-mid | **Sonnet 5.5** (sits between Opus and Sol) | Nearly Opus-level design/creativity, very fast and efficient, good medium coder. Medium-effort front-end. |
| Upper-mid | **GPT-6.1 Sol** | Near-Astra intelligence for backend and logical work; backend checking and verification. Weaker taste than Opus. |
| Mid | **GPT-6.1 Terra** | Computer use and lightweight work that is not very logical: a medium-level developer. |
| Light | **Haiku** | Trivial edits and text improvements. Decent at small taste decisions, better than Luna. |
| Lightest | **GPT-6 Luna** | Trivial mechanical edits, a tier below Haiku. Weaker taste than Haiku, but better at holding up over long-horizon repetitive work. |

## Routing rules

1. Front-end, medium effort → **Sonnet 5.5**.
2. Back-end, medium intelligence needed → **GPT-6.1 Sol**.
3. Front-end and epic (best design, decisions, taste, storytelling) → **Opus 5.5**.
4. Epic logic/backend → **Fable 5.1** or **GPT-6 Astra**.
5. Computer use, or light and not very logical → **GPT-6.1 Terra**.
6. Backend verification of Opus/Sonnet output → **Sol**.

Difficulty 1 pairs with Haiku/Luna/Terra, 2 with Sonnet/Sol/Terra, 3 with Opus/Sol,
4 with Fable 5.1/Astra/Opus. Importance sets ordering, not model choice.
