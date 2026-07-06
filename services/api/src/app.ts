import Fastify, { FastifyInstance } from 'fastify'
import websocket from '@fastify/websocket'
import prismaPlugin from './plugins/prisma'
import redisPlugin from './plugins/redis'
import positionsFeedPlugin from './plugins/positions-feed'
import { parcelRoutes } from './routes/parcels'
import { devRoutes } from './routes/dev'
import { wsRoutes } from './routes/ws'

export async function build(opts: { testing?: boolean } = {}): Promise<FastifyInstance> {
  const app = Fastify({ logger: !opts.testing })

  await app.register(prismaPlugin)
  await app.register(redisPlugin)
  await app.register(websocket)
  await app.register(positionsFeedPlugin, { testing: opts.testing })
  await app.register(parcelRoutes, { prefix: '/parcels' })
  await app.register(devRoutes, { prefix: '/dev' })
  await app.register(wsRoutes, { prefix: '/ws' })

  app.get('/health', async () => ({ status: 'ok' }))
  app.get('/metrics', async (_, reply) => {
    reply.header('Content-Type', 'text/plain')
    return '# GreenLogistics API metrics\napi_up 1\n'
  })

  return app
}
