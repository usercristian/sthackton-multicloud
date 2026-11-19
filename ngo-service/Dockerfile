ARG PYTHON_VERSION=3.11-slim

FROM python:${PYTHON_VERSION}

# Evita geração de arquivos .pyc e força logs imediatos no stdout/stderr do Kubernetes
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8081

RUN addgroup --system appgroup && adduser --system --ingroup appgroup appuser

WORKDIR /app

# Instala dependências antes de copiar o código para aproveitar o cache do Docker
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

COPY . .

RUN chown -R appuser:appgroup /app

USER appuser

EXPOSE 8081

# Executa via Gunicorn (2 workers leves adequados ao rightsizing FinOps)
CMD ["sh", "-c", "gunicorn --bind 0.0.0.0:${PORT} --workers 2 --threads 2 --access-logfile - app:app"]