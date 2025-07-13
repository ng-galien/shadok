import os
from typing import Optional

class Config:
    """Configuration de l'application"""
    
    # Serveur
    HOST: str = os.getenv("HOST", "0.0.0.0")
    PORT: int = int(os.getenv("PORT", "8000"))
    
    # Application
    APP_NAME: str = "python-hello"
    APP_VERSION: str = "1.0.0-SNAPSHOT"
    APP_DESCRIPTION: str = "Python Hello World Pod pour Shadok"
    
    # Debug
    DEBUG: bool = os.getenv("DEBUG", "false").lower() == "true"
    
    # Kubernetes
    KUBERNETES_NAMESPACE: Optional[str] = os.getenv("KUBERNETES_NAMESPACE")
    POD_NAME: Optional[str] = os.getenv("HOSTNAME")

config = Config()
