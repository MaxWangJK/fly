FROM python:3.12-slim
WORKDIR /app
COPY requirements.lock .
RUN pip install --no-cache-dir -r requirements.lock && useradd --uid 10001 --create-home fly
COPY app app
COPY alembic alembic
COPY alembic.ini .
RUN mkdir -p /var/lib/fly/storage && chown -R fly:fly /var/lib/fly /app
USER fly
EXPOSE 8000
CMD ["sh", "-c", "alembic upgrade head && exec uvicorn app.asgi:app --host 0.0.0.0 --port 8000 --workers 1 --proxy-headers --forwarded-allow-ips='*'"]
