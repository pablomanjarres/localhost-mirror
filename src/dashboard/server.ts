import { Router } from 'express';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));

export function createDashboardRouter(): Router {
  const router = Router();

  router.get('/', (_req, res) => {
    const html = readFileSync(join(__dirname, 'index.html'), 'utf-8');
    res.type('html').send(html);
  });

  return router;
}
