import fp from 'fastify-plugin'
import { FastifyPluginAsync } from 'fastify'
import { Kafka } from 'kafkajs'
import type { WebSocket } from 'ws'

declare module 'fastify' {
  interface FastifyInstance {
    positionClients: Set<WebSocket>
  }
}

const positionsFeedPlugin: FastifyPluginAsync<{ testing?: boolean }> = fp(async (app, opts: { testing?: boolean }) => {
  const clients = new Set<WebSocket>()
  app.decorate('positionClients', clients)

  if (opts.testing) return // pas de broker Kafka disponible en CI/tests

  const kafka = new Kafka({
    clientId: 'api-positions-feed',
    brokers: (process.env.REDPANDA_BROKERS || 'localhost:9092').split(',')
  })
  const consumer = kafka.consumer({ groupId: 'api-positions-feed-group' })

  await consumer.connect()
  await consumer.subscribe({ topic: 'gps.positions', fromBeginning: false })

  consumer.run({
    eachMessage: async ({ message }) => {
      if (!message.value) return
      const payload = message.value.toString()
      for (const client of clients) {
        if (client.readyState === client.OPEN) client.send(payload)
      }
    }
  }).catch((err) => app.log.error({ err }, 'positions-feed consumer crashed'))

  app.addHook('onClose', async () => { await consumer.disconnect() })
})

export default positionsFeedPlugin
