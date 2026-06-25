import { FastifyInstance } from 'fastify'
import { randomUUID } from 'crypto'

const DEMO_PARCELS = [
  { id: 'PARCEL-DEMO-001', recipient_email: 'client1@example.com', destination_lat: 48.8566, destination_lng: 2.3522 },
  { id: 'PARCEL-DEMO-002', recipient_email: 'client2@example.com', destination_lat: 48.8738, destination_lng: 2.2950 },
]

export async function devRoutes(app: FastifyInstance) {
  app.post('/seed-demo', async (request, reply) => {
    const results = await Promise.all(DEMO_PARCELS.map(d =>
      app.prisma.parcel.upsert({
        where: { id: d.id },
        update: {},
        create: {
          id: d.id,
          tracking_code: d.id,
          sender: 'Demo',
          recipient_email: d.recipient_email,
          destination_lat: d.destination_lat,
          destination_lng: d.destination_lng,
          status: 'IN_TRANSIT',
          events: { create: { id: randomUUID(), status: 'CREATED', message: 'Colis démo créé' } }
        }
      })
    ))
    return reply.status(201).send(results)
  })


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