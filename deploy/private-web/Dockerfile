FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /srv/toolbox
COPY AuthorizationBridge/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt gunicorn==23.0.0
COPY AuthorizationBridge/ /srv/toolbox/
RUN useradd --uid 10001 --create-home toolbox
USER toolbox
EXPOSE 8080
CMD ["gunicorn", "--workers", "2", "--threads", "2", "--timeout", "120", "--bind", "0.0.0.0:8080", "web_test_bridge:app"]
