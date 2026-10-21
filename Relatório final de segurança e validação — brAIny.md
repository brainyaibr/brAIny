# Relatório final de segurança e validação — brAIny

**Data de corte das evidências:** 21/10/2026, 14:11 (America/Sao_Paulo)

**Escopo:** backend FastAPI, frontend React/Vite, persistência, OAuth/sessões, ownership, arquivos, quotas, jobs, build, documentação e Preview local do WebDev.
**Base Git observada:** `778c81b7fb7e63b2d05c06e2bf437ed38dab2d5a` (`fix: derive session key from strong csrf root`). Esse SHA identifica o último commit existente antes das alterações locais desta rodada; **não é um checkpoint da versão validada**.

> **Veredito:** as correções revisadas estão consistentes com a suíte local, e nenhum defeito crítico foi reproduzido na validação executada. Ainda assim, esta revisão **não comprova prontidão irrestrita para produção**: MySQL real, os sete cenários que chamam IA, restore, carga de operações caras e o novo rollout não foram validados. No corte de evidências acima, as alterações locais ainda não tinham checkpoint/publicação; qualquer release posterior deve ser conferido separadamente pelo estado retornado pelo WebDev.

## 1. Resumo executivo

Foram preservados React/Vite e FastAPI, sem substituição da arquitetura nem alteração intencional dos contratos da API. A coordenação produtiva foi mantida em MySQL gerenciado, sem Redis; os testes locais usaram SQLite temporário isolado. O frontend compila com Vite 6.4.5 e o backend passou na suíte local executável (197 aprovados, cinco testes MySQL ignorados) após a correção do caso de corpo HTTP `application/json` acima de 1 MiB.

A revisão visual cobriu os nove tamanhos solicitados. No painel **Perguntar**, sem sessão, o estado de autenticação foi confirmado: aviso de login presente, composer e envio desabilitados, CTA de login habilitado e faixa de uso mensal corretamente ausente para usuário não autenticado. O CTA foi conectado ao fluxo OAuth. Não foi aberta uma sessão OAuth real; portanto, a exibição do consumo para um usuário autenticado não foi verificada visualmente nesta rodada.

Durante o walkthrough foram corrigidos defeitos do frontend: a consulta de projetos era iniciada antes da confirmação de sessão e convertia o `401` esperado em toast; o painel Ask não recebia o callback de login nem `authLoaded`; e uma falha de rede em `/api/auth/me` era apresentada como logout. Projetos agora são consultados após a autenticação, Ask distingue verificação em andamento, erro recuperável com retry e sessão anônima, e o seletor de arquivos foi alinhado à allowlist de MIME do chat. Essas duas últimas mudanças foram verificadas por revisão de código/build, não por uma sessão OAuth real.

## 2. Achados por gravidade

### Crítico

- **Nenhuma vulnerabilidade crítica foi reproduzida** nos testes automatizados e nas verificações limitadas desta rodada. Isso não significa que a aplicação esteja livre de vulnerabilidades; a cobertura e as integrações não executadas continuam limitando o veredito.

### Alto — bloqueadores para uma alegação irrestrita de produção

1. **Coordenação MySQL não foi exercitada nesta rodada.** Cinco testes de integração MySQL foram ignorados porque `BRAINY_TEST_MYSQL_URL` não foi configurada e o Docker CLI não está disponível neste ambiente. A suíte passou com fixtures SQLite; isso não prova locks, leases, quota/rate-limit distribuídos ou migrações no serviço MySQL gerenciado.
2. **Os sete cenários funcionais que fazem chamadas reais ao provedor não foram repetidos.** O ambiente detecta um provedor LLM, mas não há tabela real de preços nem teto mensal global configurados para a execução. Como os cenários podem gerar consumo externo e persistem projetos, não foi inventado preço nem foi assumida autorização para uma rodada sem teto. O resultado histórico 7/7 de 06/10/2026 permanece histórico e não é apresentado como validação atual.
3. **O último rollout não foi revalidado.** Há registro anterior de falha de startup por chave de sessão forte ausente/inválida. A configuração WebDev consultada lista `JWT_SECRET`, `BRAINY_CSRF_SECRET` e `BRAINY_SESSION_SECRET` como configurados em produção, mas os valores não foram lidos e seu comprimento/força não foi verificado. Nenhum novo deploy foi feito.
4. **Backup e restauração MySQL + Manus Storage continuam sem evidência de execução.** O procedimento seguro está documentado, mas não há RPO/RTO demonstrado nem restauração ponta a ponta validada.
5. **As sete jornadas de geração, edição e autocorreção com provedor real não foram validadas após as mudanças atuais.** O runner `scripts/test_scenarios.py` não foi executado; não se confunde a suíte determinística com testes reais de geração.

### Médio

- O smoke de carga foi deliberadamente pequeno e somente de leitura: 120 `GET /api/health`, concorrência 16, todos HTTP 200, p50 29,30 ms e máximo 113,83 ms. Não é teste de capacidade, de jobs, MySQL ou provedores externos.
- A tela de uso mensal para sessão autenticada não foi visualmente exercitada por falta de uma sessão de teste OAuth. O código condiciona o strip a `user && usage`; a rota de uso é coberta pela suíte, mas não se afirma uma validação visual logada.
- O preview do código gerado não tem isolamento completo de egress: `connect-src 'none'` bloqueia conexões programáticas, mas a CSP ainda permite scripts de CDNs em allowlist, fontes externas e imagens HTTPS. Recursos passivos podem gerar requisições externas; não inserir segredos/dados sensíveis no preview. O bloqueio mais estrito permanece uma tarefa de hardening, pois pode afetar compatibilidade com projetos que usam recursos externos.
- O `pytest` produziu cinco avisos de depreciação (integração `httpx`/Starlette e handlers `on_event`). Não falharam, mas merecem migração planejada.
- Não foi possível construir/validar a imagem Docker nesta máquina (`docker` CLI ausente). O teste de runtime feito foi com Uvicorn local, build React e SQLite temporário.
- A configuração WebDev consultada está com `publishing.auto_publish=true`. No corte das evidências, não houve push para `main`, checkpoint ou acionamento de publicação; o sucesso de deployment então observado correspondia somente ao SHA-base `778c81b7fb7e63b2d05c06e2bf437ed38dab2d5a`, não às alterações locais.

### Baixo — corrigido durante esta rodada

- **403 em vez de 413 para JSON acima de 1 MiB:** o teste havia falhado antes da correção porque CSRF interceptava a requisição antes do limite de corpo. O middleware de limite ficou mais externo, mantendo CSRF ativo; a suíte final passou, inclusive o teste `test_request_body_limit_rejeita_json_maior_que_um_megabyte`.
- **Gate anônimo com erro visual indevido:** a listagem privada não é mais solicitada antes de confirmar usuário, evitando toast de erro em uma sessão deslogada.
- **CTA do Ask sem handler:** o painel agora recebe `authLoaded` e callback que inicia `/api/auth/login`.
- **Falha de `/api/auth/me` confundida com logout:** Ask agora mostra erro de sessão recuperável e botão “Tentar novamente”, em vez de convidar o usuário a entrar quando o backend não confirmou o estado.
- **Tipos de anexo divergentes:** o seletor Ask oferecia TXT/CSV/Markdown/JSON e MIME genéricos `image/*`/`audio/*`, enquanto o endpoint do chat aceitava apenas a allowlist de raster/PDF/MP3/WAV/M4A/MP4. O filtro foi alinhado aos tipos efetivamente aceitos; a validação server-side permanece a fronteira de segurança.
- **Scripts de instalação/desenvolvimento sem bit executável:** `scripts/run.sh` e `scripts/dev.sh` foram corrigidos para modo Git `100755`, coerente com os comandos `./scripts/...` documentados. `bash -n` passou.

## 3. Correções e controles verificados

- Autenticação Manus OAuth integrada; sessão assinada, associação da sessão ao estado de usuário e revogação via `session_version` no logout. CORS e validação fail-closed estão centralizados na configuração.
- Autorização e ownership são verificados no backend para projetos, arquivos, assets, histórico e jobs; a interface não é tratada como fronteira de segurança.
- CSRF permanece ativo nas mutações; a ordem da proteção de tamanho foi corrigida sem desativá-lo.
- Há allowlist server-side de modelos; quotas por usuário/operação/período; reservas atômicas e guarda global configurável; registro agregado por projeto/usuário; timeout, teto de tentativas, cancelamento e contabilização de chamadas incertas.
- Fila, idempotência, rate limit e claims/leases de produção usam MySQL gerenciado, sem Redis no desenho aprovado. Testes SQLite não substituem teste multi-instância MySQL.
- SVG usa parser XML defensivo e allowlist; ZIP e nomes de arquivo são verificados contra traversal, caminhos absolutos, aliases Windows, colisões e limites de volume/tamanho.
- Dockerfile usa usuário não privilegiado, runtime `PORT` (fallback 3000) e health path `/api/health`; o container ainda não foi construído localmente nesta rodada.
- O código gerado é mostrado em iframe sandbox do navegador; o backend não executa o JavaScript gerado em processo privilegiado.

## 4. Evidências executadas em 21/10/2026

| Verificação | Resultado | Escopo/limite |
|---|---|---|
| `PYTHONPATH=backend backend/.venv/bin/python -m pytest backend/tests -q -rs` | **197 passed, 5 skipped, 5 warnings, 16,85 s** | Execução final pós-revisão; os cinco skips são `test_mysql_coordination.py`, por falta de `BRAINY_TEST_MYSQL_URL`; inclui o teste de 413. |
| Execução inicial anterior ao ajuste de middleware | **1 failed, 196 passed, 5 skipped** | Falha reproduzida: 403 no corpo com `Content-Type: application/json` >1 MiB. Após reordenar o middleware, a suíte local executável foi repetida e passou. |
| `npm --prefix frontend audit --audit-level=low` | **0 vulnerabilidades** | Lock do frontend atual. |
| `npm --prefix frontend run build` | **Passou**, Vite 6.4.5 | 37 módulos; JS 206,45 kB bruto (65,81 kB gzip), CSS 63,33 kB bruto (11,58 kB gzip). |
| `pip-audit -r backend/requirements.lock` | **No known vulnerabilities found** | Varredura do lock de runtime, sem atualização automática ampla. |
| `pyright` | **0 errors, 0 warnings, 0 informations** | Depois das alterações do backend. |
| `bash -n scripts/run.sh scripts/dev.sh`; `git diff --check` | **Passou** | Inclui os modos executáveis corrigidos. |
| Preview: `GET /api/health` | **200** | Servidor local isolado; banco SQLite em `/tmp`. |
| Preview: `GET /manus-routes.json` | **200** | Manifest contém a rota `/` e não recebeu fallback HTML. |
| Preview sem sessão: `GET /api/auth/me`; `GET /api/projects` | **200 authenticated=false**; **401** | O backend nega a listagem sem sessão; a revisão de código também confirmou um estado de erro/retry distinto para falha de verificação da sessão. |
| DOM do painel Ask em 1280 px | **0 px de overflow horizontal** (`scrollWidth=clientWidth=1280`); login visível/habilitado; textarea e envio desabilitados; faixa de uso oculta | Sessão não autenticada; não valida a visão logada. |
| Smoke de carga local | **120/120 HTTP 200**, concorrência 16; p50 29,30 ms; max. 113,83 ms | Somente `GET /api/health`, sem mutações ou IA; não é teste de capacidade. |
| Capturas WebDev | **9 larguras** | Abaixo; revisão visual, não medição programática de `scrollWidth` em cada viewport. |

### Breakpoints visuais

As imagens registram a tela inicial responsiva, sem sessão, e permanecem no pacote de código:

| Largura | Evidência |
|---:|---|
| 320 px | [320.png](validacao-visual/320.png) |
| 375 px | [375.png](validacao-visual/375.png) |
| 390 px | [390.png](validacao-visual/390.png) |
| 430 px | [430.png](validacao-visual/430.png) |
| 768 px | [768.png](validacao-visual/768.png) |
| 1024 px | [1024.png](validacao-visual/1024.png) |
| 1280 px | [1280.png](validacao-visual/1280.png) |
| 1440 px | [1440.png](validacao-visual/1440.png) |
| 1920 px | [1920.png](validacao-visual/1920.png) |

No walkthrough do painel Perguntar, o texto “Entre para conversar” e o botão “Entrar ou criar conta” ficaram visíveis. O navegador confirmou que o composer e o botão de envio permanecem desabilitados sem usuário. Nenhuma mensagem, upload, geração ou chamada billable foi enviada. A captura visual do gate logado não foi feita.

## 5. Cenários funcionais não repetidos nesta rodada

| # | Cenário registrado no projeto | Situação atual |
|---:|---|---|
| 1 | Geração de landing page/site | Não executado: usa LLM real e pode consumir quota/custo. |
| 2 | Jogo 2D com canvas e game loop | Não executado pelo mesmo motivo. |
| 3 | Aplicativo de lista de tarefas | Não executado pelo mesmo motivo. |
| 4 | Geração e sanitização de SVG | Não executado através do runner provider-backed; sanitização determinística é coberta pela suíte local. |
| 5 | Assistente corrigindo bug off-by-one | Não executado pelo runner provider-backed. |
| 6 | Autocorreção após erro de runtime e anti-loop | Não executado pelo runner provider-backed. |
| 7 | Edição incremental por conversa/ops | Não executado pelo runner provider-backed. |

O arquivo histórico `docs/testes/resultado.json` e o resultado 7/7 de 06/10/2026 não foram sobrescritos nem reapresentados como atuais. Para repetir os sete cenários com segurança, primeiro configurar preços reais por modelo/imagem, teto global autorizado e uma base de teste isolada; depois executar os cenários e registrar o JSON novo.

## 6. Banco, dados e segurança operacional

Todos os testes automatizados desta rodada usaram fixtures SQLite isoladas. O smoke do Preview usou `DATABASE_URL` vazio e `BRAINY_DB_PATH=/tmp/brainy-preview-test.db`. Não foi usado o MySQL gerenciado nem houve migração, limpeza ou deleção de dados compartilhados. O runner provider-backed, um backup/restore e o teste MySQL não foram executados.

A aplicação não deve ser anunciada como “totalmente segura” nem como pronta para operação comercial multi-instância até que o teste de coordenação MySQL, o rollout com segredo forte, as integrações reais de OAuth/Storage/LLM sob orçamento e a restauração de backup sejam comprovados. A documentação de backup em `README.md` é procedimento proposto, não prova de restore.

## 7. Arquivos alterados/adicionados

**Aplicação/configuração:** `.env.example`, `Dockerfile`, `backend/app/auth.py`, `config.py`, `coordination.py`, `db.py`, `generators.py`, `images.py`, `jobs.py`, `llm.py`, `main.py`, `prompts.py`, `ratelimit.py`, `sandbox.py`, `usage.py`, `backend/requirements-dev.txt`, `backend/requirements.lock`, `backend/requirements.txt`.

**Testes:** `backend/tests/conftest.py`, `backend/tests/e2e/test_flows.py`, `test_auth_cookies.py`, `test_context_manager.py`, `test_core.py`, `test_generated_assets.py`, `test_idempotency.py`, `test_jobs.py`, `test_preview_security.py`, `test_production_guards.py`, `test_project_attachments.py`, `test_ratelimit.py`, `test_usage.py`, e os novos `test_audit_regressions.py`, `test_model_policy.py`, `test_scenario_runner.py`.

**Frontend:** `frontend/package.json`, `frontend/package-lock.json`, `frontend/src/App.jsx`, `frontend/src/api.js`, `frontend/src/components/AskPanel.jsx`, `PreviewPanel.jsx`, `VisualCalibration.jsx`, `frontend/src/styles.css`.

**Operação/documentação:** `README.md`, `TODO.md`, `plan.md`, `pyrightconfig.json`, `scripts/run.sh`, `scripts/dev.sh`, `scripts/test_scenarios.py`, `docs/02-arquitetura.md`, `docs/04-testes.md`, este relatório e as nove imagens em `docs/validacao-visual/`.

## 8. Estado de publicação e próximos passos

No corte das evidências, a implantação WebDev confirmada estava em `success` no SHA-base `778c81b7fb7e63b2d05c06e2bf437ed38dab2d5a`; ela não continha as alterações locais revisadas. O URL publicado do baseline é `https://brainy-u5rjrsj7.manus.space/`. O Preview usado para esta validação é `https://8328-injxusvwumbu0xepk596v-6254b77d.us4.manus.computer/`. Como `publishing.auto_publish=true`, qualquer checkpoint de `main` pode iniciar publicação automática; reporte somente um resultado posterior se o WebDev o confirmar.

Para avançar a produção com evidência completa: configurar ou confirmar preços reais e teto global; executar os sete cenários contra uma base isolada; habilitar MySQL descartável para os cinco testes de coordenação; validar o startup do container e as variáveis de deploy sem expor segredos; confirmar o login OAuth real e a faixa de uso em sessão autenticada; e realizar uma restauração MySQL + Storage em staging. Qualquer checkpoint/publish requer autorização explícita e deve respeitar o estado de auto-publicação do projeto.
