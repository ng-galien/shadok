FROM node:20-alpine
WORKDIR /app
COPY dist ./dist
USER 1000:1000
EXPOSE 8080
CMD ["node", "dist/server.js"]
