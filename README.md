# brAIny — do pedido ao projeto validado

O brAIny é uma aplicação SaaS que transforma instruções em linguagem natural em sites, aplicações web, jogos 2D, imagens e código. O produto preserva o fluxo React/FastAPI existente: criação e edição incremental por conversa, preview isolado, validação do artefato, assistência de código, histórico, autenticação, tarefas assíncronas e exportação ZIP.

Este repositório contém uma implementação de produção em evolução, não uma garantia de segurança absoluta. Consulte [o relatório de auditoria e validação](docs/06-relatorio-final-seguranca-e-validacao.md) para resultados datados, limitações e itens que ainda impedem uma aprovação irrestrita de produção.

## Instalação local

Pré-requisitos: Python 3.11 ou superior, Node.js 22 e npm 10.9.2. A imagem Docker fixa o gerenciador npm; para desenvolvimento local, use versões compatíveis com `frontend/package.json` e `frontend/package-lock.json`.

```bash
cp .env.example .env
# Edite .env e configure o endpoint/modelo/credencial que você está autorizado a usar.
./scripts/run.sh
```

O script cria uma virtualenv, instala as dependências Python da lockfile e compila o frontend com o lockfile npm. A aplicação local escuta em `http://localhost:8080` por padrão. Para hot reload:

```bash
./scripts/dev.sh
```

O modo local usa SQLite em `BRAINY_DB_PATH`; não o utilize como substituto da base compartilhada de produção. Para desenvolver testes, instale primeiro `backend/requirements.lock` e depois as dependências de `backend/requirements-dev.txt`. Os testes automatizados configuram um SQLite temporário isolado e não devem apontar para o banco gerenciado.

## Configuração

Todas as chaves privadas pertencem ao backend ou ao ambiente gerenciado. Nunca coloque credenciais em `frontend/`, em prompts, em arquivos do projeto gerado ou em logs. `.env.example` documenta nomes e formatos, mas não contém valores de produção.

| Variável | Uso |
|---|---|
| `BRAINY_LLM_BASE_URL`, `BRAINY_LLM_API_KEY`, `BRAINY_LLM_MODEL` | Endpoint e credencial do provedor configurado. O backend rejeita modelos fora de `BRAINY_ALLOWED_MODELS`. |
| `BRAINY_ALLOWED_MODELS` | Lista explícita de modelos que a API aceita; configure também o modelo padrão dentro dela. |
| `BRAINY_MODEL_PRICES_JSON` | Tarifas reais configuradas por modelo e por mil tokens. Não há tarifa implícita nem valor presumido. |
| `BRAINY_IMAGE_PROVIDER`, `BRAINY_IMAGE_*`, `BRAINY_IMAGE_PRICES_JSON` | Provedor raster opcional, modelo e preço real por imagem. O startup exige preço quando um provedor pago de imagem está habilitado. |
| `BRAINY_GLOBAL_MONTHLY_BUDGET_USD` | Teto global mensal, explícito e positivo. Sem orçamento e preços configurados, produção não inicia. |
| `BRAINY_PLAN_USAGE_QUOTAS_JSON`, `BRAINY_USER_USAGE_QUOTAS_JSON` | Overrides mensais por plano e por ID interno de usuário; a configuração padrão do código permanece quando um override não é fornecido. |
| `BRAINY_LLM_MAX_TOKENS`, `BRAINY_LLM_TIMEOUT`, `BRAINY_LLM_RETRIES` | Limites da chamada LLM. Retries automáticos são restritos a respostas conhecidas como repetíveis; erros ambíguos não são repetidos cegamente. |
| `BRAINY_MAX_REPAIR_ATTEMPTS`, `BRAINY_MAX_JOB_ATTEMPTS`, `BRAINY_JOB_TIMEOUT_SECONDS`, `BRAINY_JOB_STREAM_TIMEOUT` | Limites de autocorreção, tentativas, deadline do job e duração do stream. O código valida faixas máximas. |
| `DATABASE_URL` | Em produção, MySQL/MariaDB gerenciado com TLS. SQLite só é aceito para desenvolvimento/testes isolados. |
| `MANUS_API_URL`, `MANUS_API_KEY` | Acesso ao Manus Storage e APIs gerenciadas. No deploy, devem ser valores injetados pelo projeto/plataforma, não copiados para o frontend. |
| `MANUS_PROJECT_ID`, `MANUS_OAUTH_PORTAL_URL`, `MANUS_OAUTH_API_URL` | Configuração de Manus OAuth fornecida pela plataforma. |
| `MANUS_JWT_SECRET`, `BRAINY_SESSION_SECRET`, `JWT_SECRET`, `BRAINY_CSRF_SECRET` | Segredos fortes para sessão/CSRF. Produção valida apenas a presença e força mínima, sem incluir os valores em mensagens de erro. Use os segredos protegidos do ambiente de deploy. |
| `BRAINY_PUBLIC_ORIGIN`, `BRAINY_CORS_ORIGINS` | Origem HTTPS canônica de OAuth e origens CORS exatas. Não use `*` em produção. |
| `BRAINY_ENV`, `BRAINY_PORT`, `PORT`, `BRAINY_DATA_DIR`, `BRAINY_DB_PATH` | Modo e runtime. `PORT` prevalece no container; SQLite e diretórios locais não são duráveis em produção. |
| `BRAINY_IDEMPOTENCY_TTL` | Retenção de respostas de operações idempotentes concluídas. |

As quotas usam períodos mensais UTC, validação exclusivamente no backend e reservas atômicas para chamadas concorrentes. O sistema registra chamadas e tentativas, limita tokens por usuário/operação e considera conservadoramente chamadas cujo resultado ficou incerto. O snapshot mostra `estimated` somente quando existem preços para o consumo contabilizado; nos demais casos, o status é incompleto, não US$ 0. É uma estimativa, não uma fatura do provedor.

Os limites de rate limiting atuais são definidos por operação em `backend/app/ratelimit.py`: leitura, chat, geração de projeto, reparo, imagem, upload e pesquisa têm contadores próprios por janela. Em produção, o MySQL compartilhado é obrigatório; indisponibilidade falha fechada com `503`. Os identificadores e os endereços IP não são persistidos como texto na chave, e os caminhos dinâmicos são agrupados em buckets de cardinalidade limitada.

## Funcionalidades e limites de arquivos

O preview executa o projeto gerado apenas no navegador, dentro de iframe sandbox sem `allow-same-origin`. O backend valida sintaxe com `node --check`, mas não executa JavaScript gerado no processo do servidor. Erros recebidos do iframe não iniciam autocorreção automática por padrão; reparo continua disponível por ação explícita do usuário.

Os uploads têm limite global de 12 MiB, com verificações de extensão, MIME e conteúdo real. Corpos JSON da API têm limite de 1 MiB; o endpoint multipart admite o tamanho do upload mais uma margem de protocolo. Cada projeto pode ter até 200 arquivos, 2 MiB por arquivo e 20 MiB no total. Nomes são normalizados e validados, incluindo aliases Windows e colisões após normalização. O ZIP é verificado antes da escrita e preserva arquivos legítimos sem permitir ZIP Slip, caminhos absolutos, traversal ou colisões que sobrescrevam arquivos.

SVGs passam por parsing XML defensivo (`defusedxml`), allowlist explícita de elementos/atributos, bloqueio de eventos, scripts, referências externas e limites de tamanho, profundidade e número de nós. SVGs servidos recebem CSP restritiva e `nosniff`. Downloads de imagens do provedor aceitam somente HTTPS para endereços públicos, não seguem redirects, não herdam proxy de ambiente, verificam o MIME raster e limitam o tamanho lido.

## Deploy, backup e recuperação

O `Dockerfile` compila React/Vite e empacota FastAPI na porta `3000` (ou na variável `PORT`), inclui `/api/health` e inicia como UID não privilegiado. A imagem lê segredos e a conexão MySQL em runtime; não os exige durante a compilação. A infraestrutura de deploy precisa habilitar server e MySQL gerenciado, Storage durável, OAuth, segredos de produção e uma origem HTTPS/CORS coerente. **Esta rodada não publicou nem alterou o deploy.**

O container tem filesystem temporário. Projetos e coordenação ficam no banco; ativos são armazenados pelo serviço Manus Storage. Não trate `/app/data`, o ZIP exportado de um projeto ou a cópia deste repositório como backup integral dos registros e objetos de produção.

Procedimento seguro recomendado, antes de migrações ou intervenções: acione snapshot/export do MySQL no painel do provedor gerenciado; guarde o artefato cifrado e com acesso restrito fora do repositório; registre data, versão e identificador do banco. Confirme separadamente qual mecanismo de retenção/exportação de objetos se aplica ao Manus Storage. Para recuperar, primeiro restaure em ambiente isolado de staging, valide conectividade, schema, contagens e referências a assets, e só então planeje qualquer cutover com autorização. Não execute import, truncate, drop ou restore diretamente no banco compartilhado durante testes.

No estado registrado deste relatório, a restauração de ponta a ponta (MySQL + Storage) e os backups automatizados não foram executados nem verificados. Portanto, o procedimento acima é operacionalmente seguro como orientação, mas ainda não é evidência de um RPO/RTO ou de recuperação testada.

## Testes

```bash
# backend (SQLite isolado por teste)
PYTHONPATH=backend .venv/bin/python -m pytest backend/tests -q -rs

# frontend
npm --prefix frontend run build
npm --prefix frontend audit --audit-level=low

# MySQL local descartável: somente se Docker estiver disponível
# O compose usa uma base local brainy_test, nunca DATABASE_URL de produção.
docker compose -f docker-compose.test.yml up --build --abort-on-container-exit
```

O runner em `scripts/test_scenarios.py` contém sete cenários funcionais que chamam um servidor real e podem invocar um provedor externo de IA. Eles não são testes unitários offline e podem consumir quotas/custo do provedor configurado. A execução histórica 7/7 de 6 de outubro de 2026 está preservada em `docs/04-testes.md`; ela não substitui uma execução após as alterações atuais.

O resultado datado desta revisão, inclusive casos passados, falhos, não executados e motivos, está em [docs/04-testes.md](docs/04-testes.md) e em [docs/06-relatorio-final-seguranca-e-validacao.md](docs/06-relatorio-final-seguranca-e-validacao.md).

## Estrutura

- `frontend/`: React/Vite, cliente de API, painéis de histórico, conversa e preview.
- `backend/app/`: rotas FastAPI, autenticação, configuração, persistência MySQL/SQLite, rate limit/idempotência, fila de jobs, geração IA, Storage, sanitização de assets e exportação.
- `backend/tests/`: regressões unitárias, integração, segurança, autorização e fluxos E2E.
- `scripts/`: inicialização local e runner dos sete cenários provider-backed.
- `docs/`: arquitetura, operabilidade, testes e auditorias com carimbo de data.

## Documentos

- [Arquitetura atual](docs/02-arquitetura.md)
- [Jobs assíncronos](docs/09-jobs-assincronos.md)
- [Hardening de produção](docs/14-hardening-p0.md)
- [Histórico e estado atual dos testes](docs/04-testes.md)
- [Auditoria de produção](docs/05-auditoria-produção.md)
- [Relatório final desta revisão](docs/06-relatorio-final-seguranca-e-validacao.md)
