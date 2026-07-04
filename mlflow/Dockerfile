FROM python:3.12-slim

RUN pip install --no-cache-dir mlflow

EXPOSE 5000

# SQLite backend + local artifact store, both under /data (volume-mounted).
CMD ["mlflow", "server", \
     "--host", "0.0.0.0", \
     "--port", "5000", \
     "--backend-store-uri", "sqlite:////data/mlflow.db", \
     "--artifacts-destination", "/data/artifacts"]
