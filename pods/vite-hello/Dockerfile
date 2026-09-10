FROM node:20-alpine
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY index.html ./
COPY src ./src
USER 1000:1000
EXPOSE 8080
CMD ["./node_modules/.bin/vite", "--host", "0.0.0.0", "--port", "8080"]
