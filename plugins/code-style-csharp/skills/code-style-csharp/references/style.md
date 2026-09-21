# C# / Unity conventions

C# and Unity rules only. Shared rules live in `code-style-common`. If a rule conflicts, this file wins.

## Naming

- Types, methods, properties, events, enums: PascalCase.
- Private fields, locals, parameters: camelCase, no leading `_`.
- Parameter names use full words and stay short (`TakeDamage(int amount)` is fine; `TakeDamage(int dmg)` and `TakeDamage(int incomingDamageAmountValue)` are not).
- Interfaces keep the `I` prefix (`IHealth`).
- Inspector-visible fields use `[SerializeField] private`. Do not expose serialization with public fields.
- Keep Unity message names as the engine defines them: `Awake`, `Start`, `Update`, `OnEnable`, and the rest.
- File name matches the primary type in the file.

```csharp
[SerializeField] private GameObject playerRoot;

public interface IDamageable
{
    void TakeDamage(int amount);
}

public sealed class PlayerHealth : MonoBehaviour, IDamageable
{
    [SerializeField] private int maxHealth;

    public void TakeDamage(int amount)
    {
        maxHealth -= amount;
    }
}
```

## Types and syntax

- Use `var` when the right-hand side already makes the type obvious (`new`, `GetComponent<T>`, lambdas). Otherwise write the explicit type.
- Keep the current file's namespace, primary constructor, and `record` style. Do not rewrite them unprompted.
- No comments. No `///` XML docs.
- Exception messages are written in Chinese.

```csharp
var health = GetComponent<PlayerHealth>();
Dictionary<string, Transform> sockets = BuildSockets();
throw new InvalidOperationException("未配置 playerRoot");
```

## No defensive programming

- Do not add just-in-case null checks on `GetComponent`, serialized references, or required dependencies.
- Missing references or components must fail. Do not silently `return` or invent a default.
- Do not use empty `try/catch` or swallow exceptions in Unity lifecycle methods.
- Do not re-check in `Update` or other per-frame paths what `Awake`/`Start` already guaranteed.

Bad:

```csharp
var health = GetComponent<PlayerHealth>();
if (health != null)
{
    health.TakeDamage(1);
}
```

Good:

```csharp
GetComponent<PlayerHealth>().TakeDamage(1);
```

## Unity

- Prefer the project's existing `MonoBehaviour` / `ScriptableObject` structure. Do not turn new behavior into static C# helpers without a reason.
- If a dependency can be serialized, do not `Find` / `FindObjectOfType` at runtime.
- Prefer events, coroutines, or existing schedulers over dumping logic into `Update`.
- Match the current assembly: `asmdef`, namespaces, and cross-assembly references.

## Tooling

- Follow the repo's existing Editor / Rider / `dotnet` / Unity formatter, analyzers, and tests. Do not add a second toolchain.
