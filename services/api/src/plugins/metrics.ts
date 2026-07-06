import fp from 'fastify-plugin'
import { FastifyPluginAsync } from 'fastify'
import client from 'prom-client'

const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Durée des requêtes HTTP en secondes',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5]
})

const httpRequestsTotal = new client.Counter({
  name: 'http_requests_total',
  help: 'Nombre total de requêtes HTTP',
  labelNames: ['method', 'route', 'status_code']
})

const metricsPlugin: FastifyPluginAsync = fp(async (app) => {
  client.collectDefaultMetrics()

  app.addHook('onRequest', async (request) => {
    request.metricsStart = process.hrtime.bigint()
  })

  app.addHook('onResponse', async (request, reply) => {
    const route = request.routeOptions.url ?? request.url
    const labels = {
      method: request.method,
      route,
      status_code: String(reply.statusCode)
    }
    const durationSec = request.metricsStart
      ? Number(process.hrtime.bigint() - request.metricsStart) / 1e9
      : 0
    httpRequestDuration.observe(labels, durationSec)
    httpRequestsTotal.inc(labels)
  })

  app.get('/metrics', async (_request, reply) => {
    reply.header('Content-Type', client.register.contentType)
    return client.register.metrics()
  })
})

declare module 'fastify' {
  interface FastifyRequest {
    metricsStart?: bigint
  }
}

export default metricsPlugin
