# Shared coding conventions

Apply these rules in every language. If a language pack restates a rule, the language pack wins.

## Scope

- Change only what the task needs. No drive-by refactors, no drive-by formatting, no extra diff.
- Match existing names, folders, and abstractions. Do not introduce a second style.
- When deleting code, also delete now-dead references, imports, and tests.

## Parameter names

- Do not abbreviate parameter names. Use full words (`button` not `btn`, `count` not `cnt`, `index` not `idx`).
- Keep names short. Keep only the words that distinguish meaning (`damage` not `incomingDamageAmountValue`).
- Established full forms may be short, but do not truncate (`id`, `url`, `http` are fine; `mgr`, `cfg`, `tmp` are not).

## No comments

- Do not write line comments, block comments, or doc comments (XML, JSDoc, docstrings).
- Do not commit commented-out code.
- Express intent with names and structure, not comments.

## No defensive programming

- Do not add just-in-case null checks, type checks, fallbacks, or default values.
- Do not add broad `try/catch` to hide programmer errors.
- Handle only failures the task or the caller contract requires. Let everything else fail fast.
- Do not re-validate premises a previous layer already guaranteed.

## Errors

- Exception and user-facing error messages must be written in Chinese.
- Handle errors or rethrow them. No empty `catch`. No swallowed exceptions.
- When catching, keep enough context and do not change the failure semantics unless the task says so.

## Dependencies and secrets

- Reuse libraries and versions already in the project before adding a dependency.
- Do not commit secrets, tokens, `.env` files, credentials, or production data.
- Do not put secrets in source, fixtures, or samples.

## Collaboration

- Keep public APIs, exported symbols, and persisted formats backward compatible unless the task requires a breaking change.
- Update tests that cover changed behavior. Do not introduce a new test framework for that.
