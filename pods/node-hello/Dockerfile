FROM node:18-alpine

# Métadonnées
LABEL app.kubernetes.io/name="node-hello" \
      app.kubernetes.io/part-of="shadok-pods" \
      app.kubernetes.io/version="1.0.0"

# Variables d'environnement
ENV NODE_ENV=production \
    PORT=3000 \
    HOST=0.0.0.0

# Répertoire de travail
WORKDIR /app

# Installation des dépendances système
RUN apk add --no-cache \
    curl \
    && rm -rf /var/cache/apk/*

# Copie des fichiers de dépendances
COPY package*.json ./

# Installation des dépendances
RUN npm ci --only=production && npm cache clean --force

# Copie du code source
COPY src/ ./src/

# Création d'un utilisateur non-root
RUN adduser -D -s /bin/sh appuser
USER appuser

# Exposition du port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

# Commande de démarrage
CMD ["npm", "start"]
