# The GuYo backend as one image: the same start-up as the Procfile (migrate, seed, check, serve).
FROM python:3.13-slim

ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 PIP_NO_CACHE_DIR=1
WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY . .

EXPOSE 8000
# One worker by default (a 1 GB server); WEB_CONCURRENCY raises it on a bigger one.
CMD ["sh", "-c", "alembic upgrade head && python -m app.seed && (python -m app.multilingual_backfill || echo 'multilingual self-check failed, starting anyway') && python -m app.account_deletion purge && exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers ${WEB_CONCURRENCY:-1} --proxy-headers --forwarded-allow-ips='*'"]
