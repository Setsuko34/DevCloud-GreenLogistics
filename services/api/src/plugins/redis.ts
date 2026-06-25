import fp from 'fastify-plugin'
import { FastifyPluginAsync } from 'fastify'
import Redis from 'ioredis'

declare module 'fastify' {
  interface FastifyInstance {
    redis: Redis
  }
}

const redisPlugin: FastifyPluginAsync = fp(async (app) => {
  const redis = new Redis(process.env.REDIS_URL || 'redis://localhost:6379', {
    maxRetriesPerRequest: 0,
    enableOfflineQueue: false,
  })
  app.decorate('redis', redis)
  app.addHook('onClose', async () => { redis.disconnect() })
})

export default redisPlugin
