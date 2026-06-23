import Fastify, { FastifyInstance } from 'fastify'
import prismaPlugin from './plugins/prisma'
import redisPlugin from './plugins/redis'
import { parcelRoutes } from './routes/parcels'

export async function build(opts: { testing?: boolean } = {}): Promise<FastifyInstance> {
  const app = Fastify({ logger: !opts.testing })

  await app.register(prismaPlugin)
  await app.register(redisPlugin)
  await app.register(parcelRoutes, { prefix: '/parcels' })

  app.get('/health', async () => ({ status: 'ok' }))
  app.get('/metrics', async (_, reply) => {
    reply.header('Content-Type', 'text/plain')
    return '# GreenLogistics API metrics\napi_up 1\n'
  })

  return app
}
