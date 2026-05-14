#!/bin/bash
cd /Users/salmankhan/StudioProjects/self-healing-agent
source venv/bin/activate
uvicorn backend.main:app --reload --port 8000
