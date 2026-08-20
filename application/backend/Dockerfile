FROM python:3.13-slim

RUN apt-get update \
    && apt-get upgrade -y \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN python -m pip install --no-cache-dir --upgrade pip \
    && python -m pip install --no-cache-dir -r requirements.txt \
    && python -m pip uninstall -y pip

COPY . .

RUN adduser --disabled-password --gecos "" app \
    && chown -R app:app /app

USER app

EXPOSE 5000
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--access-logfile", "-", "--error-logfile", "-", "--capture-output", "--log-level", "info", "app:app"]
