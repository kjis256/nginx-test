# ---------- Base Image ----------
FROM nginx:latest

# ---------- Maintainer Info ----------
LABEL maintainer="kjis256@heliosen.co.kr"
LABEL description="Custom Nginx image for mybalance-stg/app"

# ---------- Set timezone ----------
ARG TZ=Asia/Seoul
ENV TZ=${TZ}
RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && echo ${TZ} > /etc/timezone

# ---------- Copy Application Files ----------
# (빌드된 정적 파일들이 ./dist 또는 ./public 같은 경로에 있다고 가정)
COPY ./dist /usr/share/nginx/html

# ---------- Copy Nginx Configuration ----------
# 필요 시 직접 작성한 conf 파일을 아래 위치에 넣으세요
COPY ./nginx/default.conf /etc/nginx/conf.d/default.conf

# ---------- Expose Port ----------
EXPOSE 80

# ---------- Healthcheck ----------
HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD curl -f http://localhost/ || exit 1

# ---------- Start Nginx ----------
CMD ["nginx", "-g", "daemon off;"]
