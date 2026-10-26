# syntax=docker/dockerfile:1.28.0@sha256:bb22d9815c728170f72750f4e5b0d672e06176142e1d602c7e66c050100b7e5b
FROM cgr.dev/chainguard/python:latest-dev@sha256:894aed3297d91283e1fc4c542f5374a4b5f3726134fda7c94eaa539342be1e05 AS builder
WORKDIR /app
RUN python -m venv --without-pip /app/venv
COPY requirements.txt .
RUN --mount=type=cache,target=/home/nonroot/.cache/pip,uid=65532,gid=65532 \
    pip --python /app/venv/bin/python install -r requirements.txt

FROM cgr.dev/chainguard/python:latest@sha256:b6248c85ba9b97e1e61b30197f309cc4d21661f889fefa5268f0a7bc530dad46
WORKDIR /app
COPY --from=builder /app/venv /app/venv
COPY app.py .
ENV PATH="/app/venv/bin:$PATH"
USER 65532
EXPOSE 5000
ENTRYPOINT ["python", "/app/app.py"]