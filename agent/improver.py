"""Prompt improvement logic for the self-healing agent.

The PromptImprover saves previous prompts, rewrites the active prompt for a
specific root cause, and guarantees a stricter prompt is returned.
"""

from __future__ import annotations

import warnings
from typing import Any

try:
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", FutureWarning)
        import google.generativeai as genai
except ImportError as exc:
    raise ImportError(
        "google-generativeai is required. Fix with: pip install google-generativeai"
    ) from exc

from config.settings import GEMINI_MODEL_NAME, GOOGLE_API_KEY, IMPROVED_SYSTEM_PROMPT_TEMPLATE


class PromptImprover:
    """Rewrite system prompts and keep a history of previous versions."""

    def __init__(self) -> None:
        self.prompt_history: list[str] = []
        self.model = self._build_model()

    def improve(self, current_prompt: str, root_cause: Any) -> str:
        """Save the current prompt and return a stricter prompt for the root cause."""
        self.prompt_history.append(current_prompt)

        try:
            new_prompt = self._improve_with_gemini(current_prompt, root_cause)
        except Exception as exc:
            print(f"⚠️ Gemini prompt improvement failed; using local rewrite. Error: {exc}")
            new_prompt = self._improve_locally(root_cause)

        if not self._is_strictly_better(current_prompt, new_prompt, root_cause):
            new_prompt = self._improve_locally(root_cause)

        return new_prompt

    def _build_model(self):
        """Create the Gemini model used for prompt rewriting."""
        if not GOOGLE_API_KEY:
            print("⚠️ GOOGLE_API_KEY is missing; PromptImprover will use local prompt rewriting.")
            return None

        try:
            genai.configure(api_key=GOOGLE_API_KEY)
            return genai.GenerativeModel(model_name=GEMINI_MODEL_NAME)
        except Exception as exc:
            print(f"⚠️ Could not initialize Gemini prompt improver: {exc}")
            return None

    def _improve_with_gemini(self, current_prompt: str, root_cause: Any) -> str:
        """Ask Gemini to rewrite the system prompt for the identified failure mode."""
        if self.model is None:
            return self._improve_locally(root_cause)

        category = self._root_cause_category(root_cause)
        explanation = self._root_cause_explanation(root_cause)
        prompt = f"""
Rewrite this customer support AI system prompt so it is strictly better for the root cause.

Root cause category: {category}
Root cause explanation: {explanation}

Current prompt:
{current_prompt}

Rules for the new prompt:
- It must use only the FAQ knowledge base.
- It must explicitly prevent the root cause category.
- It must tell the agent to say "I don't know based on the FAQ." when unsupported.
- It must be concise and production-ready.
- Return only the new system prompt text.
""".strip()
        response = self.model.generate_content(prompt)
        return getattr(response, "text", "").strip()

    def _improve_locally(self, root_cause: Any) -> str:
        """Create a deterministic improved prompt when Gemini is unavailable."""
        category = self._root_cause_category(root_cause)
        explanation = self._root_cause_explanation(root_cause)
        root_cause_text = f"{category}: {explanation}"
        base_prompt = IMPROVED_SYSTEM_PROMPT_TEMPLATE.format(root_cause=root_cause_text)

        category_rules = {
            "GUESSING": "Before answering, verify that every factual claim appears in the FAQ.",
            "IRRELEVANT": "Restate the customer's intent internally and answer that exact intent.",
            "INCOMPLETE": "Include the specific policy, timing, fee, or next step when the FAQ provides it.",
            "HALLUCINATION": "If the FAQ conflicts with a possible answer, follow the FAQ and mention no other claim.",
        }
        extra_rule = category_rules.get(category, category_rules["GUESSING"])

        return f"{base_prompt}\n- {extra_rule}"

    def _is_strictly_better(self, current_prompt: str, new_prompt: str, root_cause: Any) -> bool:
        """Check that the replacement prompt is different and targets the root cause."""
        category = self._root_cause_category(root_cause).lower()
        lowered_prompt = new_prompt.lower()

        if not new_prompt or new_prompt.strip() == current_prompt.strip():
            return False

        required_phrases = [
            "faq",
            "i don't know based on the faq",
            "do not",
        ]

        has_required_phrases = all(phrase in lowered_prompt for phrase in required_phrases)
        targets_root_cause = category in lowered_prompt or self._root_cause_keyword(category) in lowered_prompt

        return has_required_phrases and targets_root_cause

    def _root_cause_category(self, root_cause: Any) -> str:
        """Read the category from a dataclass, dict, or plain value."""
        if hasattr(root_cause, "category"):
            return str(root_cause.category).upper()

        if isinstance(root_cause, dict):
            return str(root_cause.get("category", "GUESSING")).upper()

        return str(root_cause or "GUESSING").upper()

    def _root_cause_explanation(self, root_cause: Any) -> str:
        """Read the explanation from a dataclass, dict, or plain value."""
        if hasattr(root_cause, "explanation"):
            return str(root_cause.explanation)

        if isinstance(root_cause, dict):
            return str(root_cause.get("explanation", "Prompt allowed unsupported answers."))

        return "Prompt allowed unsupported answers."

    def _root_cause_keyword(self, category: str) -> str:
        """Map root cause categories to natural language words likely found in prompts."""
        keywords = {
            "guessing": "guess",
            "irrelevant": "relevant",
            "incomplete": "specific",
            "hallucination": "unsupported",
        }
        return keywords.get(category, "guess")
