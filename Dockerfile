FROM php:8.4-cli-alpine

WORKDIR /app

COPY backend ./backend

EXPOSE 3000

CMD ["php", "-S", "0.0.0.0:3000", "-t", "backend/api"]
