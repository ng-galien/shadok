import pytest
from fastapi.testclient import TestClient
import sys
import os

# Ajouter le répertoire src au path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from main import app

client = TestClient(app)

def test_hello_text():
    """Test de l'endpoint /hello en texte plain"""
    response = client.get("/hello")
    assert response.status_code == 200
    assert response.text == "Hello World from Python Pod!"
    assert response.headers["content-type"] == "text/plain; charset=utf-8"

def test_hello_json():
    """Test de l'endpoint /hello/json"""
    response = client.get("/hello/json")
    assert response.status_code == 200
    
    json_data = response.json()
    assert json_data["message"] == "Hello World from Python Pod!"
    assert json_data["service"] == "python-hello"
    assert json_data["version"] == "1.0.0-SNAPSHOT"
    assert "timestamp" in json_data

def test_health_check():
    """Test de l'endpoint /health"""
    response = client.get("/health")
    assert response.status_code == 200
    
    json_data = response.json()
    assert json_data["status"] == "healthy"
    assert json_data["service"] == "python-hello"
    assert json_data["version"] == "1.0.0-SNAPSHOT"
    assert "uptime_seconds" in json_data
    assert json_data["uptime_seconds"] >= 0

def test_root():
    """Test de l'endpoint racine /"""
    response = client.get("/")
    assert response.status_code == 200
    
    json_data = response.json()
    assert "message" in json_data
    assert json_data["version"] == "1.0.0-SNAPSHOT"
    assert json_data["docs"] == "/docs"
    assert json_data["health"] == "/health"

def test_docs():
    """Test que la documentation Swagger est accessible"""
    response = client.get("/docs")
    assert response.status_code == 200

def test_openapi():
    """Test que le schéma OpenAPI est accessible"""
    response = client.get("/openapi.json")
    assert response.status_code == 200
    assert response.headers["content-type"] == "application/json"
