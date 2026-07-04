# Convenience commands for the vLLM experiment.
# Run from the project root. Needs `make` (Git Bash / WSL / choco install make).
# Recipes call docker compose and the PowerShell scripts in scripts/.

COMPOSE := docker compose --env-file .env -f docker-compose.local.yml
PS := powershell -NoProfile -ExecutionPolicy Bypass -File

.PHONY: help up down restart logs ps health smoke loadtest loadtest-new loadtest-docker serve-local gpu urls clean

help: ## Show this help
	@echo Local stack:
	@echo   make up              Build and start vllm, mlflow, frontend
	@echo   make down            Stop and remove all containers
	@echo   make restart         down then up
	@echo   make logs            Follow vLLM logs
	@echo   make ps              Show container status
	@echo   make health          Check if the 3 services respond
	@echo.
	@echo Test:
	@echo   make smoke           Run endpoint smoke tests
	@echo   make loadtest        Load test and log to MLflow, shared experiment
	@echo   make loadtest-new    Load test and log to a NEW timestamped experiment
	@echo   make loadtest-docker Load test in a container, no MLflow
	@echo.
	@echo Other:
	@echo   make serve-local     Run vLLM alone, no compose
	@echo   make gpu             Show GPU memory
	@echo   make urls            Print the service URLs
	@echo   make clean           down and remove built images and volumes

up: ## Build + start the full stack
	$(COMPOSE) up -d --build

down: ## Stop and remove all containers
	$(COMPOSE) down

restart: down up ## Restart the stack

logs: ## Follow vLLM logs
	$(COMPOSE) logs -f vllm

ps: ## Show container status
	$(COMPOSE) ps

health: ## Check if the 3 services respond
	@curl -sf http://localhost:8000/health >NUL 2>&1 && echo vllm     OK 200 || echo vllm     DOWN
	@curl -sf http://localhost:5000/ >NUL 2>&1 && echo mlflow   OK 200 || echo mlflow   DOWN
	@curl -sf http://localhost:3000/api/model >NUL 2>&1 && echo frontend OK 200 || echo frontend DOWN

smoke: ## Run endpoint smoke tests
	$(PS) scripts/smoke.ps1

loadtest: ## Load test + log to MLflow (shared experiment)
	$(PS) scripts/loadtest.ps1

loadtest-new: ## Load test + log to a NEW timestamped MLflow experiment
	$(PS) scripts/loadtest.ps1 -NewExperiment

loadtest-docker: ## Load test in a container (no MLflow)
	$(COMPOSE) --profile test run --rm loadtest

serve-local: ## Run vLLM alone, no compose
	$(PS) scripts/serve_local.ps1

gpu: ## Show GPU memory
	nvidia-smi --query-gpu=memory.total,memory.used,memory.free --format=csv

urls: ## Print service URLs
	@echo vLLM      http://localhost:8000
	@echo MLflow    http://localhost:5000
	@echo Frontend  http://localhost:3000/chat

clean: ## down + remove built images and volumes
	$(COMPOSE) down --rmi local -v
