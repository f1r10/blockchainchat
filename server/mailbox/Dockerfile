FROM node:20-alpine
WORKDIR /app
RUN mkdir -p /app/data
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 4000
CMD ["node", "index.js"]
