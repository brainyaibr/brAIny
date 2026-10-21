FROM node:22-bookworm-slim AS frontend-build
WORKDIR /app/frontend
COPY frontend/package.json frontend/package-lock.json ./
RUN npm install --global npm@10.9.2 --no-audit --no-fund \
    && npm ci --no-audit --no-fund
COPY frontend/ ./
RUN npm run build

FROM python:3.11-slim AS runtime
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    BRAINY_ENV=production \
    BRAINY_HOST=0.0.0.0 \
    BRAINY_PORT=3000
WORKDIR /app
COPY backend/requirements.txt ./backend/requirements.txt
COPY backend/requirements.lock ./backend/requirements.lock
RUN pip install --no-cache-dir -r backend/requirements.lock
COPY backend/ ./backend/
COPY --from=frontend-build /app/frontend/dist ./frontend/dist
COPY frontend/public ./frontend/public
RUN mkdir -p /app/data/assets \
    && chown -R 10001:10001 /app/data
USER 10001:10001
EXPOSE 3000
CMD ["sh", "-c", "exec uvicorn app.main:app --app-dir backend --host 0.0.0.0 --port ${PORT:-3000}"]
