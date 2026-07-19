# TIL: GLM-5.1 vs GLM-5.2 Token Usage

**Specs at a glance** ([Z.ai](https://z.ai/blog/glm-5.2), [LLM Stats](https://llm-stats.com/models/compare/glm-5.2-vs-glm-5.1), [Artificial Analysis](https://artificialanalysis.ai/models/comparisons/glm-5-2-vs-glm-5-1)):

| Feature | GLM-5.1 | GLM-5.2 |
|---|---|---|
| Max input | 200K | 1M (5×) |
| Max output | 128K | 131K |
| Reasoning | Fixed | `high` / `max` / off |
| Max thinking budget | ~16.7K | ~36.7K |

**The core tradeoff** — GLM-5.2's "max" mode more than doubles thinking tokens vs GLM-5.1, but dropping to "high" cuts consumption by >half while keeping ~98% of max capability on coding/agentic tasks ([r/LocalLLaMA](https://www.reddit.com/r/LocalLLaMA/comments/1uar4e2/glm_52_98_of_max_level_intelligence_with_less/), [Unsloth](https://unsloth.ai/docs/models/glm-5.2)).

**Use-case verdicts:**
- **Coding refactor:** GLM-5.2 burns 3–5× more output tokens (8K–12K hidden thinking for a 2K patch). Force "high" in Cline/Roo Code.
- **Large doc lookup (>200K):** GLM-5.2 ~20% more efficient — single-prompt ingest beats GLM-5.1's forced chunking ([Verdent AI](https://www.verdent.ai/guides/what-is-glm-5-2)).
- **Math/logic:** 1:35 input→output ratio; a 1K prompt can trigger the full 36.7K thinking budget. Correct where 5.1 fails, but costly.
- **Multi-turn chat:** GLM-5.1 wins on cost; 5.2 overthinks simple replies.

**Pricing parity** — both ~$1.40/1M input, ~$4.40/1M output on standard providers; DeepInfra charges $0.205/1M for cached input on 5.1, huge for agentic workloads that resend stable prefixes ([DeepInfra](https://deepinfra.com/blog/glm-5-1-model-overview), [gate.ai](https://gate.ai/blog/glm-5-1-z-ai-specs-pricing-api-use-cases)).

**TL;DR:** Upgrade to 5.2 for 1M context or flawless logic — keep it on `"high"`. Stick with 5.1 for predictable, budget-sensitive conversational workloads.

More: [BenchLM](https://benchlm.ai/compare/glm-5-1-vs-glm-5-2) · [DeepInfra GLM-5.2](https://deepinfra.com/blog/glm-5-2-pricing-benchmarks-cost-comparison)