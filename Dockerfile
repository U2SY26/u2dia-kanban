FROM python:3.12-slim

WORKDIR /app

# server.py + web/ 복사 (외부 패키지 불필요)
COPY server.py .
COPY web/ web/

# 데이터 영속성을 위한 볼륨
VOLUME /app/data

EXPOSE 5555

ENV DB_PATH=/app/data/agent_teams.db

CMD ["python", "server.py", "--host", "0.0.0.0", "--port", "5555", "--no-browser"]
