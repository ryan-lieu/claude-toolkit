Vendored from https://github.com/anthropics/claude-code-playground/tree/569c528/claude-code/mods/token-weather (Apache-2.0, Anthropic sample, "as-is, without support").
Commit 569c528 (2026-10-01). Screenshots left out.
Change (claude-toolkit, 2026-10-28): the AbovePrompt hook now calls next(e) and stacks its band above what other mods drew, instead of replacing their bands; it also reads hasSurvey and bodyColumns from e.props, where the API puts them.
