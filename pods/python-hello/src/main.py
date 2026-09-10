from fastapi import FastAPI
from fastapi.responses import PlainTextResponse
import datetime
import time
import os

try:
    from .config import config
    from .models import HelloResponse, HealthResponse
except ImportError:
    # Fallback for direct imports
    from config import config
    from models import HelloResponse, HealthResponse

# Startup time used to calculate uptime
start_time = time.time()

# Create the FastAPI application
app = FastAPI(
    title=config.APP_NAME,
    description=config.APP_DESCRIPTION,
    version=config.APP_VERSION,
    debug=config.DEBUG
)

@app.get("/hello", response_class=PlainTextResponse)
async def hello_text():
    """Return the greeting as plain text"""
    return "Hello World from Python Pod!"

@app.get("/hello/json", response_model=HelloResponse)
async def hello_json():
    """Return a structured JSON greeting"""
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
    """Kubernetes health check endpoint"""
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
    """Root endpoint with documentation links"""
    return {
        "message": f"Welcome to {config.APP_NAME}",
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
