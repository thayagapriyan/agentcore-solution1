import express from 'express';

const app = express();
const port = parseInt(process.env.PORT ?? '8080', 10);

app.use(express.json());

app.get('/ping', (_req, res) => {
  res.json({ status: 'ok' });
});

app.post('/invocations', (_req, res) => {
  res.json({ result: 'hello' });
});

app.listen(port, () => {
  console.log(`listening on :${port}`);
});
