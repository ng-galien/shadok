from pydantic import BaseModel
from typing import Optional
import datetime

class HelloResponse(BaseModel):
    """Response model for endpoint /hello/json"""
    message: str
    service: str
    version: str
    timestamp: datetime.datetime
    pod_name: Optional[str] = None
    namespace: Optional[str] = None

class HealthResponse(BaseModel):
    """Response model for endpoint /health"""
    status: str
    service: str
    version: str
    timestamp: datetime.datetime
    uptime_seconds: float
