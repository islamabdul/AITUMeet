FROM python:3.12-slim
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 DATABASE_PATH=/app/data/aitumeet.sqlite3
WORKDIR /app
RUN useradd --create-home --uid 10001 bot && mkdir /app/data && chown bot:bot /app/data
COPY --chown=bot:bot aitumeet ./aitumeet
COPY --chown=bot:bot run.py ./run.py
USER bot
VOLUME ["/app/data"]
CMD ["python", "run.py"]
