# TODO (Phase 2): run with a read-only root filesystem (ECS readonlyRootFilesystem)

FROM python:3.13-slim
WORKDIR /app

# Create least-privilege user for the container
RUN adduser --disabled-password --gecos "" \
    --shell /usr/sbin/nologin appuser

# Copy the required version of uv
COPY --from=ghcr.io/astral-sh/uv:0.13.1 /uv /bin/uv

# Set the path of the virtual environment and ensure output stays unbuffered for precise logging
ENV PATH="/app/.venv/bin:$PATH"
ENV PYTHONUNBUFFERED=1

# Copy dependencies
COPY pyproject.toml uv.lock README.md ./

# Install dependencies, copy the project folder, and install the project
RUN uv sync --frozen --no-dev --no-install-project
COPY src/ /app/src/
RUN uv sync --frozen --no-dev
COPY alembic/ /app/alembic/
COPY alembic.ini ./

RUN /usr/local/bin/python -m pip uninstall -y pip

USER appuser

EXPOSE 8000

CMD ["uvicorn", "findings_platform.main:app", "--host", "0.0.0.0", "--port", "8000"]