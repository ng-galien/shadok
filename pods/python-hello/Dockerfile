FROM python:3.11-alpine

# Métadonnées
LABEL app.kubernetes.io/name="python-hello" \
      app.kubernetes.io/part-of="shadok-pods" \
      app.kubernetes.io/version="1.0.0"

# Variables d'environnement
ENV PYTHONPATH=/app/src \
    PYTHONUNBUFFERED=1 \
    PORT=8000 \
    HOST=0.0.0.0

# Répertoire de travail
WORKDIR /app

# Installation des dépendances système
RUN apk add --no-cache \
    curl \
    && rm -rf /var/cache/apk/*

# Copie et installation des dépendances Python
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copie du code source
COPY src/ ./src/

# Création d'un utilisateur non-root
RUN adduser -D -s /bin/sh appuser
USER appuser

# Exposition du port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8000/health || exit 1

# Commande de démarrage
CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
