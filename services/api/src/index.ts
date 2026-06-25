import { build } from './app'

async function main() {
  const app = await build()
  await app.listen({ port: Number(process.env.PORT) || 3000, host: '0.0.0.0' })
}

main().catch((err) => { console.error(err); process.exit(1) })
