import { FastifyInstance } from 'fastify'
import { randomUUID } from 'crypto'
import { Kafka } from 'kafkajs'

const NOTIFY_RADIUS_KM = 1
const ARRIVAL_RADIUS_KM = 0.1

function distanceKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371
  const dLat = (lat2 - lat1) * Math.PI / 180
  const dLng = (lng2 - lng1) * Math.PI / 180
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * Math.sin(dLng / 2) ** 2
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
}

export async function devRoutes(app: FastifyInstance) {
  const kafka = new Kafka({
    clientId: 'api-dev-seed',
    brokers: (process.env.REDPANDA_BROKERS || 'localhost:9092').split(',')
  })
  const producer = kafka.producer()
  let producerReady: Promise<void> | null = null
  const ensureProducer = () => producerReady ??= producer.connect()
  app.addHook('onClose', async () => { if (producerReady) await producer.disconnect() })

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

    const parcel = await app.prisma.parcel.findUnique({ where: { id: parcel_id } })
    if (parcel && parcel.status !== 'DELIVERED') {
      if (parcel.status === 'CREATED') {
        await app.prisma.parcel.update({
          where: { id: parcel_id },
          data: {
            status: 'IN_TRANSIT',
            events: { create: { id: randomUUID(), status: 'IN_TRANSIT', message: 'Colis en cours de livraison' } }
          }
        })
      }

      const dist = distanceKm(lat, lng, parcel.destination_lat, parcel.destination_lng)

      if (dist <= ARRIVAL_RADIUS_KM) {
        await app.prisma.parcel.update({
          where: { id: parcel_id },
          data: {
            status: 'DELIVERED',
            events: { create: { id: randomUUID(), status: 'DELIVERED', message: 'Colis livré' } }
          }
        })
      } else if (dist <= NOTIFY_RADIUS_KM) {
        try {
          await ensureProducer()
          await producer.send({
            topic: 'parcels.events',
            messages: [{
              key: parcel_id,
              value: JSON.stringify({
                parcel_id,
                tracking_code: parcel.tracking_code,
                event: 'near_5min',
                recipient_email: parcel.recipient_email
              })
            }]
          })
        } catch (err) {
          app.log.error({ err }, 'failed to publish near_5min')
        }
      }
    }

    return reply.status(201).send({ key, driver_id: driverId, lat, lng, parcel_id })
  })

  app.delete('/seed-position/:driver_id', async (request, reply) => {
    const { driver_id } = request.params as { driver_id: string }
    await app.redis.del(`driver:${driver_id}:pos`)
    return reply.status(204).send()
  })
}
