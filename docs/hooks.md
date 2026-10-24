# Hooks: Freigaben, Fragen, Nachrichten-Socket und Codex

Stand: 22.10.2026. Wie Claude Code und Codex mit notchais Hooks umgehen; darauf beruhen `notchai-hook`, `HookOutput` und das Session-Buch.

## Wie geprüft wurde

In einer Linux-Testumgebung:

- **Claude Code 2.1.308** und **codex-cli 0.163.0**.
- Beide liefen gegen einen kleinen lokalen Test-Server, der die Modell-API nachahmt: Er antwortet mit einem vorgegebenen Werkzeugaufruf (`Bash: touch erlaubt.txt` bzw. `AskUserQuestion`) und danach mit „Fertig.“. So feuern alle Hooks wie im echten Betrieb, ohne Konto und ohne Kosten.
- Jede Umgebung hatte ein eigenes Wegwerf-Home (`HOME=…/claude-spike/home`, `CODEX_HOME=…/codex-spike/home`) und projektlokale Einstellungen (`.claude/settings.local.json`). Echte Einstellungen wurden nicht angefasst.
- Claude Code lief einmal mit `-p` und einmal interaktiv in einem Pseudo-Terminal, damit der normale Freigabe-Dialog sichtbar wird.
- Die Test-Hooks waren Shell-Skripte, die ihre Eingabe und Umgebung mitschreiben und je nach Versuch erlauben, ablehnen, eine Antwort liefern oder 8 s schlafen.

Offen bleibt nur, was es ausschließlich auf dem Mac gibt (Claude-App, Codex-App, VS Code, cmux). Das steht am Ende unter „Offene Punkte“.

## 1. Freigabe-Verhalten (`PermissionRequest`)

**Antwort:**

- Der normale Freigabe-Dialog erscheint **sofort und parallel** zum Hook. Im Versuch kam er nach 0,8 s, während der Hook noch 8 s schlief. Der Hook hält den Agenten also nie auf.
- Wer zuerst entscheidet, gewinnt:
  - Antwortet der Hook später mit der Allow-JSON, während der Dialog noch offen ist, schließt Claude Code den Dialog und führt aus („Allowed by PermissionRequest hook“).
  - Antwortet man zuerst im Terminal, läuft der Agent sofort weiter. **Der Hook-Prozess wird dabei nicht beendet**, er wartet bis zu seinem eigenen Ende weiter.
- Leere Ausgabe (Exit 0, kein stdout) heißt „keine Entscheidung“: Der Dialog bleibt einfach stehen. Ohne Dialog (`-p`) wird das Werkzeug dann abgelehnt.
- Ablehnen mit `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"In notchai abgelehnt"}}}` kommt beim Modell als Fehler mit genau diesem Text an.
- Etwa 6 s nach dem Dialog meldet Claude Code zusätzlich `Notification` mit `notification_type: "permission_prompt"` und `message: "Claude needs your permission"`.

**Beleg:** Pseudo-Terminal-Mitschnitt: Dialog „Do you want to proceed?“ bei 0,83 s, Hook-Start bei 0,83 s, Hook-Ende bei 8,8 s. Mit `allowlate` (4 s warten, dann erlauben) steht bei 4,98 s „Ran 1 shell command · Allowed by PermissionRequest hook“, ohne Tastendruck. Mit Tastendruck „1“ bei 2,5 s ist die Datei sofort angelegt, und `hook-sleepend` wird trotzdem erst bei 8 s geschrieben.

**Folgen für notchai:**

- „Nie blockieren“ ist durch Claude Code selbst garantiert. Die Wartezeit (`approvalTimeoutSeconds`) begrenzt nur noch, wie lange die Notch eine Anfrage zeigt.
- Kommt für dieselbe Session ein weiteres Ereignis, während eine Anfrage offen ist (`PostToolUse`, `PostToolUseFailure`, `PreToolUse`, `UserPromptSubmit`, `Stop`, `StopFailure`, `SessionEnd`), wurde sie anderswo beantwortet. Das Session-Buch entfernt sie dann und meldet ihre ID, damit die App dem wartenden Hook sofort „keine Entscheidung“ schickt. `Notification` mit `permission_prompt` gehört zur selben Anfrage und räumt nichts auf.
- Hook-Eingabe bei `PermissionRequest` enthält zusätzlich `prompt_id`, `effort` und `permission_suggestions`. Unbekannte Felder ignoriert `HookEvent` ohnehin.

## 2. Fragen beantworten (`AskUserQuestion` über `PreToolUse`)

**Antwort:** Der Hook antwortet mit `permissionDecision: "allow"` und `updatedInput`. `updatedInput` **ersetzt** die ganze Werkzeug-Eingabe, also kommt das ursprüngliche `questions`-Array unverändert zurück, ergänzt um `answers`:

```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow",
  "updatedInput":{"questions":[…unverändert…],"answers":{"Welche Farbe?":"Blau"}}}}
```

- Schlüssel ist der Fragetext, Wert die Beschriftung der gewählten Option.
- Mehrfachauswahl: Beschriftungen mit „, “ verbunden. Das Werkzeug nimmt auch ein Array und verbindet es selbst.
- Freitext ist erlaubt (in der Oberfläche heißt das „Other“). Der Wert ist dann einfach der getippte Text.
- „allow“ ohne `answers` reicht nicht, dann fragt Claude Code trotzdem.
- Bei `-p` ist `AskUserQuestion` abgeschaltet. Relevant ist nur der interaktive Betrieb.

**Beleg:** Interaktiver Lauf: In der Sitzung steht „User answered Claude's questions: · Welche Farbe? → Blau“, beim Modell kommt `Your questions have been answered: "Welche Farbe?"="Blau"` an. Doku: https://code.claude.com/docs/en/hooks („For `AskUserQuestion`, echo back the original `questions` array and add an `answers` object …“). Schema im Programm: `answers: record<string, string | string[]>`, Arrays werden mit `", "` verbunden.

**Folgen für notchai:** `HookOutput.questionAnswer(toolInput:answers:)` setzt `answers` in die unveränderte Eingabe. Option **und** Freitext gehen über diesen Weg, `ReplySender` ist für Fragen nicht nötig.

## 3. Nachrichten in eine laufende Claude-Session (`CLAUDE_CODE_MESSAGING_SOCKET`)

**Antwort:** Nicht als „Antwort aus der Notch“ geeignet.

- Nachrichten über den Socket kommen in der Session ausdrücklich als **Nachricht einer anderen Session** an, nicht als Eingabe des Nutzers: „Claude Code tells B's Claude that the message came from another session, not from you“ und „a message from another session never counts as your consent“.
- Je nach `crossSessionInbound` und Rechte-Modus werden sie zurückgehalten (`hold`) oder verworfen (`refuse`). Im Modus `auto` sind zurückgehaltene Nachrichten wahrscheinlich.
- Das Zeilenformat nach der optionalen Auth-Zeile `{"type":"auth","token":…}` ist nicht dokumentiert.

**Beleg:** https://code.claude.com/docs/en/cross-session-messaging. Die Variablen `CLAUDE_CODE_MESSAGING_SOCKET` und `CLAUDE_CODE_MESSAGING_TOKEN` kommen in jedem Hook an (geprüft).

**Folgen für notchai:** `ClaudeMessaging.isSupported = false`. Antworten an Claude laufen über cmux bzw. Fenster nach vorn + Zwischenablage.

## 4. Codex-Hooks

**Antwort:**

- Codex liest `$CODEX_HOME/hooks.json`, also standardmäßig `~/.codex/hooks.json`. Das Format ist dasselbe wie bei Claude: `{"hooks":{"<Ereignis>":[{"matcher":"","hooks":[{"type":"command","command":"…","timeout":5,"async":true}]}]}}`.
- Ereignisse: `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `PreToolUse`, `PermissionRequest`, `PostToolUse`, `PreCompact`, `PostCompact`, `SubagentStart`, `SubagentStop`, `Stop`, `Interrupt`.
- `async` wird unterstützt, mit zwei Ausnahmen: `SessionEnd` läuft trotzdem synchron, und bei `SessionEnd` und `Interrupt` kürzt Codex den Timeout auf 3 s (Warnungen „running async SessionEnd hook synchronously“, „clamping SessionEnd hook timeout to 3s“).
- **Wichtig: Hook-Freigabe.** Neue oder geänderte Hooks führt Codex erst aus, nachdem man sie einmal bestätigt hat. Im Terminal fragt Codex beim Start „Hooks need review“, mit den Möglichkeiten „Trust all and continue“ bzw. „Continue without trusting (hooks won't run)“. Ohne Bestätigung laufen sie stillschweigend nicht (bei `codex exec` ohne jeden Hinweis). Den Vertrauensstand speichert Codex selbst (`trusted_hash`). Ändert sich ein Hook-Kommando, muss er neu bestätigt werden („Modified since last trusted - review required“).
- Hook-Eingabe: `session_id`, `turn_id`, `transcript_path`, `cwd`, `hook_event_name`, `model`, `permission_mode`, dazu je nach Ereignis `source`, `prompt`, `stop_hook_active`, `last_assistant_message`, `reason`. In der Umgebung kommt `CODEX_HOME` an.

**Beleg:** `codex features list` → `hooks stable true`. Lauf mit `CODEX_HOME=…/codex-spike/home` und `--dangerously-bypass-hook-trust` (nur für den Versuch): `SessionStart`, `UserPromptSubmit`, `Stop` und `SessionEnd` feuern mit den Feldern oben. Ohne diesen Schalter feuert nichts. Die Texte zur Hook-Freigabe stehen im Programm.

**Folgen für notchai:**

- Pfad bleibt `~/.codex/hooks.json`. `SessionEnd` wird bei Codex ohne `async` eingetragen (schadet nicht, `notchai-hook` endet nach höchstens 300 ms).
- Nach „Codex verbinden“ sagt der Assistent: „Starte Codex einmal im Terminal und wähle bei ‚Hooks need review‘ ‚Trust all and continue‘.“ Das Hook-Kommando muss über Updates hinweg gleich bleiben (fester Pfad `~/Library/Application Support/notchai/bin/notchai-hook`), sonst fragt Codex erneut.
- notchai schreibt weiterhin nie `config.toml` und umgeht die Freigabe nie.

## 5. Codex-Rollout-Zeilen

**Antwort:** Bestätigt. Jede Zeile hat `timestamp`, `type` und `payload` (neu ist zusätzlich `ordinal`).

- `session_meta.payload`: `id` (= `session_id`), `cwd`, `originator`, `source`, `cli_version`. `originator` ist `codex_exec` bei `codex exec`. Für die Kommandozeile kennt das Programm `codex_tui` (mit Unterstrich, nicht `codex-tui`).
- `turn_context.payload.model`
- `event_msg` mit `task_started` (`model_context_window`), `token_count` (`info.last_token_usage.total_tokens`, `info.model_context_window`) und `task_complete` (`last_agent_message`).
- Prompts stehen als `response_item`/`message` mit `role: "user"` und `input_text`. Die Umgebungsangaben kommen ebenfalls als `user`-Nachricht, beginnen aber mit `<environment_context>`. Systemtexte haben die Rolle `developer`.

**Beleg:** Rollout aus dem Lauf oben (`sessions/2026/10/22/rollout-….jsonl`).

**Folgen für notchai:** Erkannt wird nur über `originator`, ohne feste Liste.

**Nachtrag 0.163 (aus dem Programm gelesen, nicht an einem echten Rollout geprüft):**

- `token_count` trägt neben `info` auch `rate_limits` (`RateLimitSnapshot`): `limit_id`, `limit_name`, `primary` und
  `secondary` mit je `used_percent`, `window_minutes` und `resets_at` (Unix-Sekunden), dazu `credits` und `plan_type`.
  Ältere Versionen schrieben `resets_in_seconds` statt `resets_at`. `rate_limits` kann `null` sein oder nur
  `limit_id` enthalten; notchai behält dann die zuletzt bekannten Werte und nimmt nur `limit_id` `codex` (oder ohne).
- Codex packt ruhende Rollouts mit zstd zu `rollout-….jsonl.zst` (`rollout/src/compression.rs`). Laufende Threads
  bleiben `.jsonl`; die gepackten liest notchai nicht. Die Entwickler-Seite zählt sie („Session-Quellen kopieren“).
- Ein weitergeführter Thread schreibt in seine alte Datei im Ordner seines Starttags. notchai sucht deshalb 45 Tage
  zurück, zählt aber nur Dateien, die innerhalb der eingestellten Session-Dauer geändert wurden.

## Sessions in den Apps

- **Claude-App:** Gewöhnliche Chats liegen nur in der Cloud; davon sieht notchai nichts. Claude-Code-Sessions in der
  App schreiben nach `~/.claude/projects` (`entrypoint: "claude-desktop"`) und führen die Hooks aus
  `~/.claude/settings.json` aus (erwartet, noch nicht auf einem Mac bestätigt).
- **Codex-App:** teilt `~/.codex` mit der Kommandozeile. Das Programm kennt die `originator` `Codex Desktop` und
  `codex_desktop`, die App setzt `__CFBundleIdentifier=com.openai.codex`. Alle Threads laufen über einen
  `app-server`-Prozess, der so lange läuft wie die App.
- **Folgen für notchai:** Ein Agent-Prozess beweist nur dann, dass eine Session offen ist, wenn er zu genau einer
  Session gehört und nicht in einer der Apps läuft. Sonst verschwindet sie nach 30 Minuten Ruhe und kommt mit neuer
  Aktivität zurück.

## Nutzungslimits

Claude Code gibt die Abo-Limits (`rate_limits.five_hour`, `rate_limits.seven_day`) nur an seine Statuszeile weiter,
nicht an Hooks und nicht ins Transkript. Die Detailansicht zeigt sie deshalb nur für Codex und verweist bei Claude
auf `/usage`.

## Claude-Transkripte

Gegengeprüft an einem Transkript aus dem Versuch (2.1.308):

- Neu sind Zeilen vom Typ `api-request-blob`. Sie enthalten ebenfalls `message.content` mit `tool_result`. Gelesen werden deshalb **nur** Zeilen vom Typ `user` und `assistant`.
- Zeilen mit `isSidechain: true` stammen von Unteragenten und zählen nicht als Prompt oder Turn.
- `system` mit `subtype: "turn_duration"` markiert das Turn-Ende zusätzlich. Maßgeblich bleibt `stop_reason: "end_turn"`.

## Umgebung der Claude-Hooks

`CLAUDE_CODE_ENTRYPOINT` ist interaktiv `cli` und bei `-p` `sdk-cli`. Außerdem kommen `CLAUDE_CODE_MESSAGING_SOCKET` und `CLAUDE_CODE_MESSAGING_TOKEN` an.

## Offene Punkte

- `CLAUDE_CODE_ENTRYPOINT` und `__CFBundleIdentifier` für Sessions in der Claude-App (erwartet `claude-desktop` bzw. `com.anthropic.claudefordesktop`) und im VS-Code-Terminal (`TERM_PROGRAM=vscode`).
- `originator` von Sessions aus der Codex-App (erwartet `Codex Desktop`, siehe oben).
- Ob die Codex-App die Hook-Freigabe genauso abfragt wie die Kommandozeile.
- Ob `rate_limits` in echten Rollouts genau so aussieht wie oben.
- cmux: Name der `CMUX_*`-Variable mit der Surface-ID.

Am einfachsten geht das, sobald notchai die Hooks eingerichtet hat: Die Entwickler-Seite der Einstellungen zeigt die zuletzt empfangenen Ereignisse mit Umgebung („Letzte Hook-Ereignisse kopieren“) und jede bekannte Session mit Herkunft und Prozess („Session-Quellen kopieren“).
