from fastapi import FastAPI
from fastapi.responses import PlainTextResponse
import datetime
import time
import os

try:
    from .config import config
    from .models import HelloResponse, HealthResponse
except ImportError:
    # Fallback pour les imports directs
    from config import config
    from models import HelloResponse, HealthResponse

# Temps de démarrage pour calculer l'uptime
start_time = time.time()

# Création de l'application FastAPI
app = FastAPI(
    title=config.APP_NAME,
    description=config.APP_DESCRIPTION,
    version=config.APP_VERSION,
    debug=config.DEBUG
)

@app.get("/hello", response_class=PlainTextResponse)
async def hello_text():
    """Endpoint simple qui retourne Hello World en texte plain"""
    return "Hello World from Python Pod!"

@app.get("/hello/json", response_model=HelloResponse)
async def hello_json():
    """Endpoint qui retourne Hello World en JSON structuré"""
    return HelloResponse(
        message="Hello World from Python Pod!",
        service=config.APP_NAME,
        version=config.APP_VERSION,
        timestamp=datetime.datetime.now(),
        pod_name=config.POD_NAME,
        namespace=config.KUBERNETES_NAMESPACE
    )

@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint pour Kubernetes"""
    current_time = time.time()
    uptime = current_time - start_time
    
    return HealthResponse(
        status="healthy",
        service=config.APP_NAME,
        version=config.APP_VERSION,
        timestamp=datetime.datetime.now(),
        uptime_seconds=uptime
    )

@app.get("/")
async def root():
    """Endpoint racine qui redirige vers la documentation"""
    return {
        "message": f"Bienvenue sur {config.APP_NAME}",
        "version": config.APP_VERSION,
        "docs": "/docs",
        "health": "/health",
        "endpoints": {
            "hello_text": "/hello",
            "hello_json": "/hello/json"
        }
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host=config.HOST,
        port=config.PORT,
        reload=config.DEBUG,
        log_level="info"
    )
