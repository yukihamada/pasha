FROM nginx:alpine
COPY *.html /usr/share/nginx/html/
COPY *.png /usr/share/nginx/html/
COPY img/ /usr/share/nginx/html/img/
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 8080
