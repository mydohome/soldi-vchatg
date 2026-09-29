FROM python:3.12-alpine
RUN apk add --no-cache tzdata && pip install --no-cache-dir openpyxl==3.1.5
WORKDIR /app
COPY app.py /app/app.py
COPY static /app/static
ENV PYTHONUNBUFFERED=1 DATA_DIR=/data
EXPOSE 8080
CMD ["python","/app/app.py"]
