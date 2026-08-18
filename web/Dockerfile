FROM node:22-alpine@sha256:c610fcdfb1d5b4740dd70c284ed3cb16bb857e0f7166196e36a5501df7a3aa32

WORKDIR /app
COPY package.json server.js ./
COPY public ./public

ENV WEB_HOST=0.0.0.0
ENV WEB_PORT=3000
EXPOSE 3000

USER node
CMD ["node", "server.js"]
