"""Tiny in-process policy memory for amortizing repeated healing work.

This is intentionally lightweight: it stores learned prompt patches and root
cause fixes for the lifetime of the Cloud Run instance. It is not a durable
database, but it lets repeated public-demo patterns avoid paying for repeated
diagnose/rewrite calls.
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class LearningMemory:
    """In-memory cache of learned policy fixes by surface and failure pattern."""

    prompt_patches: dict[str, str] = field(default_factory=dict)
    learned_rules: list[str] = field(default_factory=list)

    def get_patch(self, surface: str, category: str) -> str | None:
        return self.prompt_patches.get(self._key(surface, category))

    def remember_patch(self, surface: str, category: str, patch: str) -> None:
        self.prompt_patches[self._key(surface, category)] = patch
        if patch not in self.learned_rules:
            self.learned_rules.append(patch)

    def _key(self, surface: str, category: str) -> str:
        return f"{surface.strip().lower()}:{category.strip().upper()}"


learning_memory = LearningMemory()
