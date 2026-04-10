FROM node:20-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci --production=false

COPY tsconfig.json ./
COPY app/ ./app/
COPY src/ ./src/

RUN npm run build

CMD ["node", "dist/app/index.js"]
