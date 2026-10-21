# brAIny — Manus WebDev deployment plan (Approved)

**Status:** owner-approved; implementation may proceed. The project’s server and managed MySQL capabilities are enabled. The source remains at `/home/ubuntu/responsive-work`; the WebDev project is `/home/ubuntu/brainy`. The implementation keeps the existing React/Vite frontend, FastAPI backend, product behavior, responsive redesign, CSS design tokens, accessibility work, and public HTTP API contracts. This is a deployment and integration task, not a second visual redesign.

## Goal and product scope

Prepare the existing brAIny application for the Manus-managed WebDev runtime. Preserve project creation and refinement, live sandboxed preview, code/console views, automatic repair, project and chat history, the code assistant, image generation, research/chat, uploads, usage controls, asynchronous jobs, and ZIP export. Complete the existing composer attachment path so up to three authorized reference files can inform project creation/refinement. Do not discard existing functionality or change backend API contracts unless required to make the selected runtime work.

## Application and serving architecture

- **One container, same origin:** retain the root `Dockerfile`. Its Node 22 stage installs the existing frontend lockfile and builds Vite; its Python 3.11 stage installs the FastAPI dependencies and serves the compiled `frontend/dist`. `frontend/src/api.js` uses relative `/api/...` paths, so no separate static host or browser-visible API URL is needed.
- **Runtime:** keep the existing listener on `0.0.0.0:$PORT` with 3000 as the default, matching the WebDev Preview runtime port. Use the existing unauthenticated `GET /api/health` response as the container health path. Configure a container deployment using `Dockerfile`; do not add a separate static `build` output or custom route table unless a concrete routing check shows it is needed.
- **Route manifest:** retain `frontend/public/manus-routes.json` and verify after startup that `/manus-routes.json` returns that JSON rather than SPA fallback HTML.
- **Platform services:** use the project-provided MySQL `DATABASE_URL` and Manus runtime API credentials for LLM and storage. The WebDev runtime exposes the names `DATABASE_URL`, `MANUS_API_URL`, `MANUS_API_KEY`, `MANUS_PROJECT_ID`, `MANUS_JWT_SECRET`, `MANUS_OAUTH_PORTAL_URL`, and `MANUS_OAUTH_API_URL` (values are redacted). The existing LLM adapter already targets `MANUS_API_URL`/`MANUS_API_KEY`; a separate OpenAI/model-provider key is therefore not required if that integration remains. The default image provider is SVG, so no separate image-provider key is needed for the current default.
- **Login:** preserve the Manus OAuth flow and `webdev_app_session` cookie. Use proxy-aware cookie attributes: public HTTPS Preview/runtime cookies are `SameSite=None; Secure`; plain-HTTP local development uses `SameSite=Lax` without `Secure`, so browsers accept the cookie. Verify the browser-visible callback origin in Preview/public runtime. Do not replace authentication or alter API routes unless a concrete compatibility issue requires a minimal coordinated change.
- **Durable assets:** generated image bytes and user uploads go through the Manus Storage-backed path using runtime credentials; persist stable storage addresses and owner metadata, authorize standalone as well as project-associated image retrieval, and redirect only after checking ownership. Do not rely on container-local files for production uploads. The container filesystem is ephemeral. Project creation/refinement accepts at most three existing owner-owned image/PDF/audio/video uploads; resolve temporary read URLs inside the job only, treat file contents as untrusted data, and omit an empty attachment field to preserve legacy request/idempotency behavior.

## Approved coordination choice: managed MySQL

The owner approved using the project’s managed MySQL for distributed rate limiting, idempotency, and job coordination rather than adding an external Redis service. Implement database-backed coordination using atomic operations/transactions and job claims or leases so behavior remains shared across instances. Serialize additive startup DDL across concurrent instances with a database-scoped MySQL advisory lock while keeping SQLite initialization lock-free. Preserve the public API and fail-closed production safety. Do not silently fall back to per-process memory in production. Redis will not be required for the approved path.

## Data and security boundaries

- The source tree includes a local `data/brainy.db`. Do **not** copy that database or its user/project history to the new project by default. The managed MySQL database is shared by WebDev development and production; initialize only the application schema and avoid destructive SQL or test writes against it. Any requested data migration must be discussed separately.
- Exclude `.env`, `data/brainy.db`, `.git`, `node_modules`, and generated build output from source transfer as applicable. Keep `.env.example` with placeholders; never copy secrets into source, Git, logs, or the browser bundle.
- The platform supplies the existing Manus OAuth, LLM, storage, and managed database environment names. `MANUS_JWT_SECRET` and its published `JWT_SECRET` alias are platform-owned; do not shadow them for app configuration. Prefer a strong platform JWT for Preview-token verification and app sessions, then the app-owned `BRAINY_SESSION_SECRET`. If neither is strong, derive a distinct session key from a strong `BRAINY_CSRF_SECRET` using HMAC-SHA256 and a project-specific domain label; continue verifying any platform-signed Preview token with its platform key. Never accept a weak app-owned key for session verification, and never put secret values in source, Git, logs, or the browser bundle. Validate the production guard and real Manus login; do not invent a preview user or bypass authentication.
- Keep project visibility unchanged unless the owner separately authorizes a visibility change. Publication confirmation and who can open the URL are distinct controls. `publishing.auto_publish` is currently `true`; a push/checkpoint can trigger publication. Never treat an uncheckpointed local edit as published, and do not trigger a release unless explicitly authorized.

## Compatibilidade do banco — estado atual

The previously identified upsert mismatch is resolved in `backend/app/db.py`: `db.save_files()` selects MySQL `ON DUPLICATE KEY UPDATE` or SQLite `ON CONFLICT` by dialect. The current SQLite suite does not prove execution against managed MySQL; the five MySQL coordination tests remain a release validation item. No source SQLite records are imported.

## Existing visual direction to preserve

- **Design movement:** minimal editorial product design: bright surfaces, crisp hierarchy, restrained deep-red action color.
- **Core principles:** focus on the user’s request; low ornamentation; comfortable density; legible states.
- **Color philosophy:** white and warm grays keep generated code and preview central; deep red `#B42318` marks creation, repair, and primary actions; semantic state colors remain distinct.
- **Layout paradigm:** three functional desktop zones (navigation, conversation, result); mobile reorganizes into a full-height, tabbed workspace with accessible composer and no horizontal overflow.
- **Signature elements:** geometric red brain mark; moderate-radius outlined controls; clear preflight/status treatments.
- **Interaction philosophy:** primary actions stay reachable; busy/error states preserve context; visible keyboard focus and mobile touch targets are retained.
- **Animation:** short color/opacity transitions and a restrained generation pulse; respect reduced-motion preferences; no decorative motion.
- **Typography:** Inter for interface and JetBrains Mono for code, with compact headings and readable body measure.
- **Brand essence:** “From request to ready, with evidence”; direct, careful, reliable.
- **Brand voice:** concise action labels such as “Create project” and “Apply change”; microcopy such as “Validated before you see it.”
- **Wordmark/logo:** retain the existing br/AI/ny wordmark and geometric brain-in-red-card motif; preserve the current signature red. Set the platform’s literal HTTPS `logoUrl` to the uploaded public CDN copy of the existing SVG before checkpointing.

## Project structure to retain

- `frontend/`: React/Vite UI, `src/components/` panels and interactions, `src/styles.css` tokens and responsive system, `public/` logo and route manifest.
- `backend/app/`: FastAPI routes (`main.py`), configuration, MySQL/SQLite adapter (`db.py`), Manus OAuth, LLM, storage, generation, sandboxing, jobs, rate limiting, and idempotency.
- `backend/tests/`: existing isolated unit/regression suite.
- `scripts/`: run/dev helpers and existing scenario runner.
- Root `Dockerfile`, dependency manifests/lockfiles, `.env.example`, `app.config.ts`, and product documentation.

## Escopo ampliado de segurança, confiabilidade e validação (aprovado em 17 out 2026)

Este adendo amplia o plano anteriormente aprovado sem invalidar suas decisões de produto, design, arquitetura ou progresso. O trabalho continua no projeto e nos arquivos atuais; manter React/Vite, FastAPI, MySQL gerenciado, Manus Storage e os contratos públicos existentes sempre que viável. Não introduzir Redis nem serviços externos sem necessidade demonstrada.

### Resultados solicitados

- **Segurança e isolamento:** auditar autenticação, autorização de objeto por usuário no backend em cada endpoint protegido, sessões, OAuth, CORS, validação, rate limits, abuso e segredos em logs/erros. Projetos, conversas, arquivos e tarefas devem permanecer isolados por proprietário. Criar testes automatizados de tentativas de acesso não autorizado.
- **Geração, preview e exportação:** usar parser XML seguro, allowlist explícita de elementos e atributos compatível com recursos legítimos dos projetos e bloquear scripts, eventos e referências externas perigosas. Proteger ZIP contra caminhos absolutos, travessia, colisões/sobrescrita e excesso de nomes, arquivos ou bytes. Testar conteúdo legítimo e malicioso.
- **Motor de IA e quotas:** preservar os fluxos de site, aplicativo, jogo 2D, imagem, código e edição incremental; limitar retries/timeouts e correções; validar sucesso antes de sinalizá-lo e preservar a última versão válida. Validar modelos no backend e contabilizar operações, retries e concorrência com reservas atômicas por usuário, operação, período e limite global. Preços são configuração explícita; sem preço configurado, mostrar tokens/estimativas sem inventar cobrança. Tratar cancelamento e limites/erros dos provedores.
- **Filas e persistência:** usar o banco atual quando adequado para estados persistentes `pending`, `running`, `completed`, `cancelled` e `failed`, idempotência, controle de concorrência, timeouts e recuperação de jobs abandonados. Preservar históricos e artefatos válidos após reinicializações/falhas; detectar conflitos em edições simultâneas. Não depender de filas em memória como única fonte de verdade.
- **Dados e operação:** verificar transações, integridade entre projetos, conversas, arquivos e tarefas, índices, consultas e ciclo de conexões; preferir migrações aditivas e compatíveis. Não apagar/importar dados sem instrução, não tocar no MySQL compartilhado em testes e não executar DDL destrutivo. Documentar backup/recuperação realistas sem prometer capacidades inexistentes da plataforma.
- **Frontend e produção:** corrigir regressões reais de estado/renderização, preview, navegação, chamadas duplicadas, progresso, erros, cancelamento e retomada sem descaracterizar o design. Rever responsividade e acessibilidade. Revisar Docker, variáveis e dependências seletivamente, rede/portas, privilégios e execução de código gerado; documentar limites de isolamento/recursos que não estejam sob controle da aplicação. Não alegar alertas ou métricas inexistentes.
- **Documentação e entrega:** sincronizar README, instalação, `.env.example`, deploy, segurança, backup e recuperação com o código. Entregar relatório com gravidades, correções, arquivos, funcionalidades preservadas, resultados de cada teste, limitações e pendências. Não publicar, fazer push/checkpoint ou executar operações destrutivas sem autorização explícita.

### Estratégia de implementação e validação

1. Preservar a branch e todas as modificações já presentes; registrar baseline e separar achados confirmados de itens sem evidência. Inspecionar routers/handlers e verificações de propriedade antes de alterar controles.
2. Priorizar autorização/isolamento, segredos, uploads/SVG/ZIP e proteção de custos; adicionar regressões nos módulos afetados. Rever reserva/consumo e recuperação no MySQL sob concorrência, sem apontar testes ao banco gerenciado compartilhado.
3. Corrigir transações, jobs e geração preservando contratos API; mudanças de schema devem ser aditivas, retrocompatíveis e sem apagar dados. Preservar a última versão consistente e reportar falhas reais em vez de converter saídas parciais em sucesso.
4. Corrigir o frontend e atualizar documentação operacional após firmar o contrato do backend. Alterar dependências somente por vulnerabilidade ou incompatibilidade demonstrada.
5. Executar os sete cenários funcionais existentes: site, jogo 2D, app de tarefas, SVG, correção de código, correção de erro de execução e edição incremental; executar testes unitários, integração, autorização, arquivos, quotas, concorrência, jobs, banco e recuperação, além de build/typecheck e teste de carga compatível com o Sandbox. Isolar banco/dados de teste. Distinguir chamadas reais a provedores de testes com mock, limitar repetições/custos, registrar bloqueios e repetir somente testes afetados.
6. Não executar `git push`, checkpoint ou publicação: a entrega deste ciclo é uma cópia local consistente e verificável. Declarar explicitamente qualquer limite que impeça uso seguro em produção.

**Aprovação registrada:** o usuário aprovou o plano consolidado; a autorização cobre alterações de código e testes não destrutivos, mas não publicação ou mudanças destrutivas de dados.

## Implementation and release sequence

1. Create the WebDev ToDo with the original responsive, design-system, UX/accessibility, build, and feature-preservation clauses; register Python/JavaScript/CSS/HTML diagnostics before application source edits.
2. Import the existing source selectively, preserving the new WebDev Git binding and excluding the private SQLite database, `.env`, and generated dependency/build directories. Keep the current stack and add no application dependency unless an identified build/runtime issue requires it.
3. Implement shared rate-limit, idempotency, and job coordination on managed MySQL; preserve the dialect-specific upsert and serialized startup migrations between replicas; retain the public API, existing Docker build, route manifest, and `/api/health` unless verification reveals a concrete mismatch. Preserve the legacy no-attachment request shape while securely forwarding owner-verified references through Manus Storage for create/refine. Keep reproducible installs aligned with the committed npm lockfile and review Python dependency pinning for the clean container build.
4. Build the frontend and run the existing backend regression suite with an isolated SQLite test database. Start the WebDev Preview only after the route manifest is in place; avoid test mutations against the shared managed MySQL database. Recheck login, LLM, storage, jobs, authorized reference files, and responsive behavior after source transfer.
5. For an explicitly authorized release, inspect current WebDev configuration, fetch/integrate the canonical `main`, run affected checks, and use the checkpoint workflow. Because `publishing.auto_publish` is currently `true`, a push may immediately publish; honor the owner’s release scope and never disable or enable this setting silently.
6. Only describe a release as published after WebDev confirms successful deployment; report the exact returned version SHA and URL. Otherwise deliver the current Preview and clearly label it as a preview.

**Approval recorded:** the owner approved this plan and selected managed MySQL for rate limiting, idempotency, and job coordination. No external Redis URL is required for the approved design.
