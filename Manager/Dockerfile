# Manager — painel de gestão estático (HTML/CSS/JS + React via CDN).
FROM nginx:1.27-alpine
COPY index.html styles.css app.js /usr/share/nginx/html/
# nginx interno serve na 8080 (o gateway alcança por manager:8080).
RUN sed -i 's/listen       80;/listen 8080;/' /etc/nginx/conf.d/default.conf
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s --retries=5 \
  CMD wget -qO- http://127.0.0.1:8080/ >/dev/null 2>&1 || exit 1
