# Stage 1: Install dependencies
FROM node:18-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
# Install dependencies for sharp
RUN apk add --no-cache vips-dev
RUN npm install --production

# Stage 2: Build the final image
FROM node:18-alpine
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Expose the internal port
EXPOSE 3000

# Start the server
CMD ["node", "server.js"]
