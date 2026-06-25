import { FastifyInstance } from 'fastify'
import { randomUUID } from 'crypto'

export async function devRoutes(app: FastifyInstance) {
  app.post('/seed-position', async (request, reply) => {
    const { parcel_id, lat, lng, driver_id } = request.body as {
      parcel_id: string
      lat: number
      lng: number
      driver_id?: string
    }

    const driverId = driver_id ?? `DRV-${randomUUID().slice(0, 8).toUpperCase()}`
    const key = `driver:${driverId}:pos`
    const value = JSON.stringify({ lat, lng, ts: new Date().toISOString(), parcel_id })

    await app.redis.set(key, value, 'EX', 300)

    return reply.status(201).send({ key, driver_id: driverId, lat, lng, parcel_id })
  })

  app.delete('/seed-position/:driver_id', async (request, reply) => {
    const { driver_id } = request.params as { driver_id: string }
    await app.redis.del(`driver:${driver_id}:pos`)
    return reply.status(204).send()
  })
}