# Containerised Playwright runner — used by CI and `make e2e-docker`.
FROM mcr.microsoft.com/playwright:v1.49.1-noble

WORKDIR /work
COPY package.json tsconfig.json playwright.config.ts ./
RUN npm install --no-audit --no-fund
COPY tests/    ./tests/
COPY fixtures/ ./fixtures/
COPY scripts/  ./scripts/

ENV CI=true
CMD ["npx", "playwright", "test"]
