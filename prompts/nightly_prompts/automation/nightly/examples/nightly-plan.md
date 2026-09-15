# Ночная очередь

Описание и решения находятся в документах тикетов.
Строки очереди имеют фиксированный формат: не меняйте порядок полей.
Дополнительные пояснения пишите обычными абзацами, без чекбоксов.

- [ ] EXAMPLE-PLAN | mode=plan | status=draft | doc=docs/tickets/EXAMPLE-PLAN.md | depends=-
- [ ] EXAMPLE-IMPLEMENT | mode=implement | status=draft | doc=docs/tickets/EXAMPLE-IMPLEMENT.md | depends=-

draft — ещё не запускать; night-ready — разрешено поставить в ночную работу.
План и реализация одного тикета могут использовать одну строку: после проверки плана
человек меняет mode на implement и status на night-ready.
