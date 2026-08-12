# Slim base — small image, faster pulls/deploys
FROM python:3.12-slim

WORKDIR /app

# Install deps first so this layer caches independently of app code changes
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

# Run as a non-root user — basic container security hygiene,
# and a real talking point in interviews
RUN useradd --create-home appuser
USER appuser

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
